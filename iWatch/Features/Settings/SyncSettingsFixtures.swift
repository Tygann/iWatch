#if DEBUG
import Foundation

/// Opt-in, credential-free presentation fixtures for Simulator UI verification only.
extension AppSession {
    func applySyncSettingsFixtureIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("UITEST_MODE"),
              let index = arguments.firstIndex(of: "UITEST_SYNC_STATE"),
              arguments.indices.contains(index + 1) else { return }
        let state = arguments[index + 1]
        traktConnected = true
        traktLastError = nil
        isSyncing = state == "syncing"
        pendingTraktAccountKey = state == "setup" ? "ui-test-account" : nil
        syncProgress = isSyncing ? .downloadingHistory(120) : .complete
        lastSyncAt = Date(timeIntervalSince1970: 1793037600)
        lastCloudImportAt = lastSyncAt
        lastCloudExportAt = lastSyncAt
        cloudSyncStatus = state == "offline" ? .failed("Test connection unavailable") : .completed(lastSyncAt!)
        syncDiagnostics = SyncDiagnostics(initialBaselineComplete: true, importedMovieCount: 49,
            importedShowCount: 32, importedHistoryCount: 5127, pendingOperationCount: 0,
            processingOperationCount: 0, deadletterOperationCount: 0, duplicateCandidateCount: 0,
            lastSuccessfulPullAt: lastSyncAt, lastSuccessfulPushAt: lastSyncAt,
            lastSeenRemoteActivityAt: lastSyncAt, lastErrorDescription: nil)
        if state == "confirmation" {
            syncDiagnostics = SyncDiagnostics(initialBaselineComplete: true, importedMovieCount: 49,
                importedShowCount: 32, importedHistoryCount: 5127, pendingOperationCount: 3,
                processingOperationCount: 0, deadletterOperationCount: 0, duplicateCandidateCount: 0,
                lastSuccessfulPullAt: lastSyncAt, lastSuccessfulPushAt: lastSyncAt,
                lastSeenRemoteActivityAt: lastSyncAt, lastErrorDescription: "Test watched upload is unconfirmed.",
                changes: [1, 2, 3].map { episode in
                    SyncPendingChange(id: UUID(), title: "Example Show · S1 E\(episode)", action: "Marked watched",
                        createdAt: .now, state: episode == 1 ? .confirming : .waiting, isOnThisDevice: true)
                }, failure: .confirmation)
        } else if state == "offline" {
            syncDiagnostics.failure = .offline
            traktLastError = "Test connection unavailable"
        }
    }
}
#endif
