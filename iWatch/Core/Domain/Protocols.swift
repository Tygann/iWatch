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
    func addToWatchlist(_ items: [MediaID]) async throws
    func removeFromWatchlist(_ items: [MediaID]) async throws
    func addToHistory(_ payloads: [SyncOperationPayload]) async throws
    func removeFromHistory(historyIDs: [Int]) async throws
}
