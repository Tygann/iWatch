import Foundation
import SwiftData

nonisolated enum SyncOperationKind: String, Codable, Sendable {
    case addWatchlist
    case removeWatchlist
    case addHistory
    case removeHistory
}

nonisolated enum SyncOperationStatus: String, Codable, Sendable {
    case pending
    case processing
    case succeeded
    case deadletter
}

nonisolated struct SyncOperationPayload: Codable, Sendable {
    var mediaKind: MediaKind?
    var tmdbID: Int?
    var traktID: Int?
    var showTMDbID: Int?
    var showTraktID: Int?
    var seasonNumber: Int?
    var episodeNumber: Int?
    var watchedAt: Date?
    var historyID: Int?
}

nonisolated enum SyncPayloadCodec {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

@Model
final class SyncOperationRecord {
    var id: UUID = UUID()

    var kindRaw: String = SyncOperationKind.addWatchlist.rawValue
    var statusRaw: String = SyncOperationStatus.pending.rawValue
    var payload: Data = Data()
    var dedupeKey: String?
    var accountKey: String = ""
    var createdAt: Date = Date.distantPast
    var lastAttemptAt: Date?
    var nextAttemptAt: Date?
    var attemptCount: Int = 0
    var claimedByDeviceID: String?
    var claimedAt: Date?

    init(kind: SyncOperationKind,
         payload: Data,
         dedupeKey: String? = nil,
         accountKey: String = "",
         status: SyncOperationStatus = .pending,
         createdAt: Date = .now) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.statusRaw = status.rawValue
        self.payload = payload
        self.dedupeKey = dedupeKey
        self.accountKey = accountKey
        self.createdAt = createdAt
        self.attemptCount = 0
    }

    var kind: SyncOperationKind {
        SyncOperationKind(rawValue: kindRaw) ?? .addWatchlist
    }

    var status: SyncOperationStatus {
        get { SyncOperationStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
}

extension ISO8601DateFormatter {
    static let iWatch: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
