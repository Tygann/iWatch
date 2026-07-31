import Foundation

struct SyncDiagnostics: Equatable, Sendable {
    let initialBaselineComplete: Bool
    let pendingOperationCount: Int
    let processingOperationCount: Int
    let deadletterOperationCount: Int
    let duplicateCandidateCount: Int
    let lastSuccessfulPullAt: Date?
    let lastSuccessfulPushAt: Date?
    let lastSeenRemoteActivityAt: Date?
    let lastErrorDescription: String?

    nonisolated var hasPendingWork: Bool {
        pendingOperationCount > 0 || processingOperationCount > 0
    }

    nonisolated var hasIssues: Bool {
        deadletterOperationCount > 0 || duplicateCandidateCount > 0 || lastErrorDescription != nil
    }

    static let empty = SyncDiagnostics(
        initialBaselineComplete: false,
        pendingOperationCount: 0,
        processingOperationCount: 0,
        deadletterOperationCount: 0,
        duplicateCandidateCount: 0,
        lastSuccessfulPullAt: nil,
        lastSuccessfulPushAt: nil,
        lastSeenRemoteActivityAt: nil,
        lastErrorDescription: nil
    )
}

struct SyncIntegrityRepairSummary: Equatable, Sendable {
    let mediaMerged: Int
    let episodesMerged: Int
    let watchlistMerged: Int
    let watchedEventsMerged: Int
    let operationsMerged: Int
    let syncStatesMerged: Int
    let prunedCompletedOperations: Int

    nonisolated var totalChanges: Int {
        mediaMerged +
        episodesMerged +
        watchlistMerged +
        watchedEventsMerged +
        operationsMerged +
        syncStatesMerged +
        prunedCompletedOperations
    }

    static let empty = SyncIntegrityRepairSummary(
        mediaMerged: 0,
        episodesMerged: 0,
        watchlistMerged: 0,
        watchedEventsMerged: 0,
        operationsMerged: 0,
        syncStatesMerged: 0,
        prunedCompletedOperations: 0
    )
}
