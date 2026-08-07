import Testing
@testable import iWatch

@Suite
struct SettingsPresentationTests {
    @Test
    func homeSectionsFollowUserFacingHierarchy() {
        #expect(SettingsHomeSection.allCases.map(\.rawValue) == [
            "Preferences",
            "Sync",
            "Support",
            "Advanced"
        ])
    }

    @Test
    func shareIsHiddenUntilPublicStoreURLExists() {
        #expect(AppDistributionPresentation.appStoreURL == nil)
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
    func traktStatusUsesActionablePrecedence() {
        #expect(SettingsView.traktStatus(
            isConnecting: true,
            isSyncing: true,
            isConnected: false,
            needsAttention: true
        ) == "Connecting…")
        #expect(SettingsView.traktStatus(
            isConnecting: false,
            isSyncing: true,
            isConnected: true,
            needsAttention: true
        ) == "Syncing…")
        #expect(SettingsView.traktStatus(
            isConnecting: false,
            isSyncing: false,
            isConnected: true,
            needsAttention: true
        ) == "Needs Attention")
        #expect(SettingsView.traktStatus(
            isConnecting: false,
            isSyncing: false,
            isConnected: true,
            needsAttention: false
        ) == "Connected")
        #expect(SettingsView.traktStatus(
            isConnecting: false,
            isSyncing: false,
            isConnected: false,
            needsAttention: false
        ) == "Not Connected")
    }
}
