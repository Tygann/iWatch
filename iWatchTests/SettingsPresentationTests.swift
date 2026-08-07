import Testing
@testable import iWatch

@Suite
struct SettingsPresentationTests {
    @Test
    func homeSectionsFollowUserFacingHierarchy() {
        #expect(SettingsHomeSection.allCases.map(\.rawValue) == [
            "Preferences",
            "Sync",
            "Advanced"
        ])
    }

    @Test
    func shareCopyRemainsUsefulBeforePublicStoreURLExists() {
        #expect(AppDistributionPresentation.appStoreURL == nil)
        #expect(AppDistributionPresentation.shareText.contains("iWatch"))
        #expect(AppDistributionPresentation.shareText.contains("track"))
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
    func traktConnectionAccessoryMapsConnectionStates() {
        #expect(TraktConnectionAccessory.resolve(isConnected: false, isConnecting: false) == .connect)
        #expect(TraktConnectionAccessory.resolve(isConnected: false, isConnecting: true) == .connecting)
        #expect(TraktConnectionAccessory.resolve(isConnected: true, isConnecting: false) == .connected)
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
