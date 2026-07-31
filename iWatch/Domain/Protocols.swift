import Foundation

protocol MediaLike {
    var id: Int { get }
    var traktID: Int? { get }
    var title: String { get }
    var posterPath: String? { get }
    var rating: Double? { get }
}

nonisolated protocol TraktSyncing: Sendable {
    func currentToken() async -> TokenResponse?
    func getLastActivities() async throws -> TraktLastActivitiesDTO
    func getWatchlist() async throws -> [TraktWatchlistItemDTO]
    func getHistory(startAt: Date?) async throws -> [TraktHistoryItemDTO]
    func getActiveShowProgress() async throws -> [TraktShowProgressDTO]
    func getWatchlist(progress: (@Sendable (Int) async -> Void)?) async throws -> [TraktWatchlistItemDTO]
    func getHistory(startAt: Date?, progress: (@Sendable (Int) async -> Void)?) async throws -> [TraktHistoryItemDTO]
    func addToWatchlist(_ items: [MediaID]) async throws
    func removeFromWatchlist(_ items: [MediaID]) async throws
    func addToHistory(_ payloads: [SyncOperationPayload]) async throws
    func removeFromHistory(historyIDs: [Int]) async throws
}

extension TraktSyncing {
    func getActiveShowProgress() async throws -> [TraktShowProgressDTO] {
        []
    }

    func getWatchlist(progress: (@Sendable (Int) async -> Void)?) async throws -> [TraktWatchlistItemDTO] {
        let items = try await getWatchlist()
        await progress?(items.count)
        return items
    }

    func getHistory(startAt: Date?, progress: (@Sendable (Int) async -> Void)?) async throws -> [TraktHistoryItemDTO] {
        let items = try await getHistory(startAt: startAt)
        await progress?(items.count)
        return items
    }
}
