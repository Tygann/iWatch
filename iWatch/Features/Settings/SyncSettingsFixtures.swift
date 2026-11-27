#if DEBUG
import Foundation

/// Opt-in, credential-free presentation fixtures for Simulator UI verification only.
extension AppSession {
    func applySyncSettingsFixtureIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("UITEST_MODE"),
              let index = arguments.firstIndex(of: "UITEST_SYNC_STATE"),
              arguments.indices.contains(index + 1) else { return }
        applySyncSettingsFixture(arguments[index + 1])
    }

    func applySyncSettingsFixture(_ state: String) {
        traktConnected = true
        traktLastError = nil
        isSyncing = state == "syncing"
        pendingTraktAccountKey = state == "setup" ? "ui-test-account" : nil
        syncProgress = isSyncing ? .downloadingHistory(120) : .complete
        lastSyncAt = Date(timeIntervalSince1970: 1793037600)
        lastCloudImportAt = lastSyncAt
        lastCloudExportAt = lastSyncAt
        switch state {
        case "offline": cloudSyncStatus = .failed("Test connection unavailable")
        case "syncing": cloudSyncStatus = .exporting
        default: cloudSyncStatus = .completed(lastSyncAt!)
        }
        syncDiagnostics = SyncDiagnostics(initialBaselineComplete: true, importedMovieCount: 49,
            importedShowCount: 32, importedHistoryCount: 5127, pendingOperationCount: 0,
            processingOperationCount: 0, deadletterOperationCount: 0, duplicateCandidateCount: 0,
            lastSuccessfulPullAt: lastSyncAt, lastSuccessfulPushAt: lastSyncAt,
            lastSeenRemoteActivityAt: lastSyncAt, lastErrorDescription: nil)
        if state == "confirmation" {
            syncDiagnostics = SyncDiagnostics(initialBaselineComplete: true, importedMovieCount: 49,
                importedShowCount: 32, importedHistoryCount: 5127, pendingOperationCount: 4,
                processingOperationCount: 0, deadletterOperationCount: 6, duplicateCandidateCount: 0,
                lastSuccessfulPullAt: lastSyncAt, lastSuccessfulPushAt: lastSyncAt,
                lastSeenRemoteActivityAt: lastSyncAt, lastErrorDescription: "Test watched upload is unconfirmed.",
                changes: (1...10).map { episode in
                    SyncPendingChange(id: UUID(), title: "Example Show · S1 E\(episode)", action: episode <= 4 ? "Marked watched" : "Removed watched play",
                        createdAt: .now, state: episode <= 4 ? .confirming : .failed, isOnThisDevice: episode != 10)
                }, failure: .confirmation)
        } else if state == "offline" {
            syncDiagnostics.failure = .offline
            traktLastError = "Test connection unavailable"
        }
    }
}
#endif
