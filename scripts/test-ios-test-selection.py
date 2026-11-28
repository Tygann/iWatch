#!/usr/bin/env python3
"""Regression tests for iOS verification routing and workflow outputs."""

from pathlib import Path
import os
import subprocess
from tempfile import TemporaryDirectory
import unittest


ROOT = Path(__file__).resolve().parent.parent
SELECTOR = ROOT / "scripts/select-ios-tests.py"
COMPONENTS = "iWatch/DesignSystem/SettingsComponents.swift"
ROUTING = "scripts/select-ios-tests.py"
UI = "iWatchUITests"
SMOKE = {
    f"{UI}/{UI}/testNotificationSettingsAtStandardTextSize",
    f"{UI}/{UI}/testNotificationSettingsAtAccessibilityTextSize",
}


class RoutingTests(unittest.TestCase):
    def setUp(self):
        self.addCleanup(os.chdir, Path.cwd())
        self.repo = Path(self.enterContext(TemporaryDirectory()))
        os.chdir(self.repo)
        self.git("init", "--quiet")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.invalid")
        self.icon = (ROOT / COMPONENTS).read_text()
        self.update(COMPONENTS, self.icon)
        for source in (ROOT / UI).glob("*.swift"):
            self.update(f"{UI}/{source.name}", source.read_text())
        self.commit()
        self.base = self.git("rev-parse", "HEAD").strip()

    def git(self, *args):
        return subprocess.check_output(["git", *args], text=True)

    def update(self, filename, content="changed\n"):
        path = Path(filename)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def commit(self):
        self.git("add", "-A")
        self.git("commit", "--quiet", "--allow-empty", "-m", "Test fixture")

    def route(self, *options):
        self.commit()
        subprocess.run(
            ["python3", str(SELECTOR), self.base, "HEAD", "--outputs", "outputs", *options],
            check=True, capture_output=True, text=True,
        )
        outputs = dict(line.split("=", 1) for line in Path("outputs").read_text().splitlines())
        Path("outputs").unlink()
        ui = set(outputs["ui-selection"].split())
        for identifier in ui - {UI}:
            _, suite, method = identifier.split("/")
            self.assertIn(f"func {method}(", Path(f"{UI}/{suite}.swift").read_text())
        return outputs["simulator"], outputs["unit-tests"], ui

    def test_docs_only(self):
        self.update("AGENTS.md")
        self.update("Docs/DEVELOPMENT_WORKFLOW.md")
        self.assertEqual(self.route(), ("false", "false", set()))

    def test_selector_only(self):
        for path in (ROUTING, ".github/workflows/ios.yml", "scripts/test-ios-test-selection.py"):
            self.update(path)
        self.update("AGENTS.md")
        self.assertEqual(self.route(), ("true", "false", SMOKE))

    def test_timing_wrapper_exercises_both_test_commands(self):
        self.update("scripts/time-ios-stage.sh")
        self.assertEqual(self.route(), ("true", "true", SMOKE))

    def test_cosmetic_icon(self):
        self.update(COMPONENTS, self.icon.replace("width: 30, height: 30", "width: 32, height: 32"))
        self.assertEqual(self.route(), ("true", "false", SMOKE))

    def test_ambiguous_component_edit_runs_settings_flows_and_units(self):
        self.update(COMPONENTS, self.icon.replace(".accessibilityHidden(true)", ".accessibilityHidden(false)"))
        simulator, unit, ui = self.route()
        self.assertEqual((simulator, unit), ("true", "true"))
        self.assertTrue(SMOKE < ui)
        self.assertIn(f"{UI}/{UI}/testSettingsNavigation", ui)
        self.assertIn(
            f"{UI}/AccountAvatarUITests/testAdjustApplyAndRemovePhotoAtStandardAndAccessibilityTextSizes", ui
        )
        self.assertNotIn(f"{UI}/{UI}/testQuickWatchStandard", ui)
        self.assertNotIn(UI, ui)

    def test_mixed_cosmetic_selector_and_behavior(self):
        self.update(ROUTING)
        self.update(COMPONENTS, self.icon.replace(".foregroundStyle(.white)", ".foregroundStyle(.black)"))
        self.update("iWatch/Features/Library/ShowsView.swift")
        self.update("iWatch/Features/MediaDetail/EpisodeView.swift")
        simulator, unit, ui = self.route()
        self.assertEqual((simulator, unit), ("true", "true"))
        self.assertTrue(SMOKE < ui)
        self.assertIn(f"{UI}/{UI}/testColdLaunchShowsAccessibility", ui)
        self.assertIn(f"{UI}/{UI}/testSeasonRetryAccessibility", ui)
        self.assertNotIn(UI, ui)

    def test_selector_and_unit_test_changes(self):
        self.update(ROUTING)
        self.update("iWatchTests/SettingsPresentationTests.swift")
        self.assertEqual(self.route(), ("true", "true", SMOKE))

    def test_unit_test_only(self):
        self.update("iWatchTests/SettingsPresentationTests.swift")
        self.assertEqual(self.route(), ("true", "true", set()))

    def test_ambiguous_path_overrides_focused_routes(self):
        self.update(ROUTING)
        self.update("iWatch/Features/Settings/SettingsView.swift")
        self.update("Unexpected.swift")
        self.assertEqual(self.route(), ("true", "true", {UI}))

    def test_renamed_components_get_full_coverage(self):
        Path(COMPONENTS).rename(Path(COMPONENTS).with_name("Renamed.swift"))
        self.assertEqual(self.route(), ("true", "true", {UI}))

    def test_full_override(self):
        self.assertEqual(self.route("--full-ui"), ("true", "true", {UI}))


if __name__ == "__main__":
    unittest.main()
