import Foundation
import Testing
@testable import iWatch

@Suite
struct SettingsPresentationTests {
    @Test
    func includedCountsExplainEmptyAndSingularLibraries() {
        let empty = LibraryCounts(watchlistMovies: 0, watchlistShows: 0, watchedPlays: 0, showsInProgress: 0)
        #expect(empty.watchlistDescription == "No items yet")
        #expect(empty.historyDescription == "No watched plays yet")
        #expect(empty.progressDescription == "No shows in progress")
        let single = LibraryCounts(watchlistMovies: 1, watchlistShows: 1, watchedPlays: 1, showsInProgress: 1)
        #expect(single.watchlistDescription == "1 movie · 1 show")
        #expect(single.historyDescription == "1 play")
        #expect(single.progressDescription == "1 show in progress")
    }

    @Test
    @MainActor
    func supportReportExcludesFreeformPrivateContent() {
        var diagnostics = SyncDiagnostics.empty
        diagnostics.changes = [SyncPendingChange(id: UUID(), title: "PRIVATE_TITLE", action: "PRIVATE_ACTION",
            createdAt: .now, state: .confirming, isOnThisDevice: true)]
        let report = SyncSupportReport.make(version: "1", build: "42", connected: true,
            cloudStatus: .failed("PRIVATE_ERROR token=secret"), lastCloudActivity: nil, diagnostics: diagnostics)
        #expect(report.contains("Unconfirmed changes: 1"))
        #expect(report.contains("iCloud status: Needs Attention"))
        #expect(!report.contains("PRIVATE"))
        #expect(!report.contains("secret"))
        #expect(!report.contains(diagnostics.changes[0].id.uuidString))
    }

    @Test
    func homeSectionsFollowUserFacingHierarchy() {
        #expect(SettingsHomeSection.allCases.map(\.rawValue) == [
            "Preferences"
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
    @Test
    @MainActor
    func confirmationSummaryDescribesTheAffectedChanges() {
        #expect(TraktSyncPresentation.confirmationSummary(count: 0) == "A watched change needs checking.")
        #expect(TraktSyncPresentation.confirmationSummary(count: 1) == "1 watched change needs checking.")
        #expect(TraktSyncPresentation.confirmationSummary(count: 3) == "3 watched changes need checking.")
    }

    @Test
    @MainActor
    func traktRowNamesTheServiceWithoutHidingActionableStates() {
        func health(connected: Bool = false, connecting: Bool = false, error: String? = nil) -> TraktSyncPresentation {
            .resolve(connected: connected, connecting: connecting, settingUp: false, syncing: false,
                progress: .idle, diagnostics: .empty, error: error)
        }
        #expect(health().rowTitle == "Trakt")
        #expect(health().action == .connect)
        #expect(health(connecting: true).rowTitle == "Connecting…")
        #expect(health(error: "Sign-in expired").rowTitle == "Sign In to Trakt")
        var diagnostics = SyncDiagnostics.empty
        diagnostics.failure = .confirmation
        let pending = TraktSyncPresentation.resolve(connected: true, connecting: false, settingUp: false,
            syncing: false, progress: .idle, diagnostics: diagnostics, error: nil)
        #expect(pending.rowTitle == "Waiting for Confirmation")
    }

}
