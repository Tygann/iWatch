import Foundation
import Testing
@testable import iWatch

@Suite
struct SettingsPresentationTests {
    @Test
    func homeSectionsFollowUserFacingHierarchy() {
        #expect(SettingsHomeSection.allCases.map(\.rawValue) == [
            "Preferences",
            "Sync"
        ])
    }

    @Test
    func shareCopyIncludesCurrentInstallURL() {
        #expect(AppDistributionPresentation.shareText.contains("iWatch"))
        #expect(AppDistributionPresentation.shareText.contains("track"))
        #expect(AppDistributionPresentation.shareText.contains("testflight.apple.com/join/r6MFxreq"))
    }

    @Test
    func advancedSectionsKeepDestructiveActionsLast() {
        #expect(AdvancedSettingsSection.allCases.map(\.rawValue) == [
            "Storage",
            "Reset"
        ])
    }

    @Test
    @MainActor
    func syncHealthUsesConsistentActionablePrecedence() {
        var diagnostics = SyncDiagnostics.empty
        diagnostics.failure = .offline
        func health(connected: Bool = true, connecting: Bool = false, setup: Bool = false, syncing: Bool = false) -> TraktSyncPresentation {
            .resolve(connected: connected, connecting: connecting, settingUp: setup, syncing: syncing,
                     progress: .downloadingHistory(20), diagnostics: diagnostics, error: "Latest error")
        }
        #expect(health(connecting: true).title == "Connecting…")
        #expect(health(connected: false).action == .connect)
        #expect(health(setup: true).action == .setup)
        #expect(health(syncing: true).isWorking)
        #expect(health().title == "Connection Interrupted")
        diagnostics.failure = .confirmation
        #expect(health().action == .check)
        #expect(health().needsAttention)
        diagnostics.failure = .ambiguous
        #expect(health().title == "Review Watched History")
        #expect(health().action == .check)
    }

    @Test
    @MainActor
    func uncertainPendingChangeRemainsVisibleWithoutAnErrorString() {
        var diagnostics = SyncDiagnostics.empty
        diagnostics.changes = [SyncPendingChange(id: UUID(), title: "Episode", action: "Marked watched",
            createdAt: .now, state: .confirming, isOnThisDevice: true)]
        let health = TraktSyncPresentation.resolve(connected: true, connecting: false, settingUp: false,
            syncing: false, progress: .complete, diagnostics: diagnostics, error: nil)
        #expect(health.needsAttention)
        #expect(health.action == .check)
    }
}
