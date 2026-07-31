import Foundation

enum SyncProgress: Equatable, Sendable {
    case idle
    case checkingLocalData
    case downloadingWatchlist(Int)
    case downloadingHistory(Int)
    case downloadingShowProgress
    case saving(watchlistItems: Int, historyItems: Int)
    case uploadingChanges(Int)
    case complete
    case failed(String)

    var title: String {
        switch self {
        case .idle: return "Idle"
        case .checkingLocalData: return "Checking local data…"
        case .downloadingWatchlist: return "Downloading watchlist…"
        case .downloadingHistory: return "Downloading history…"
        case .downloadingShowProgress: return "Downloading show progress…"
        case .saving: return "Saving Trakt library…"
        case .uploadingChanges: return "Uploading local changes…"
        case .complete: return "Up to Date"
        case .failed: return "Needs Attention"
        }
    }

    var detail: String? {
        switch self {
        case let .downloadingWatchlist(count), let .downloadingHistory(count):
            return count == 1 ? "1 item received" : "\(count) items received"
        case let .saving(watchlistItems, historyItems):
            return "\(watchlistItems) watchlist items and \(historyItems) history entries"
        case let .uploadingChanges(count):
            return count == 1 ? "1 queued change" : "\(count) queued changes"
        case let .failed(message):
            return message
        default:
            return nil
        }
    }
}

struct SyncDiagnostics: Equatable, Sendable {
    let initialBaselineComplete: Bool
    let importedMovieCount: Int
    let importedShowCount: Int
    let importedHistoryCount: Int
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
        importedMovieCount: 0,
        importedShowCount: 0,
        importedHistoryCount: 0,
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
