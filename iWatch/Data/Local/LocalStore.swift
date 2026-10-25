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
    // Kept inside the existing payload to preserve the CloudKit schema.
    var originDeviceID: String? = nil
    var mutationAt: Date? = nil
    var historyRequestStartedAt: Date? = nil
    var historyRequestRejected: Bool? = nil
    var historyKnownIDs: [Int]? = nil
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
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer()
            if let seconds = try? value.decode(Double.self) { return Date(timeIntervalSince1970: seconds) }
            let string = try value.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: value, debugDescription: "Invalid operation date")
        }
        return decoder
    }()
}

@Model
final class SyncOperationRecord {
    var id: UUID = UUID()
    var generationID: String = ""

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
         createdAt: Date = .now,
         generationID: String = "") {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.statusRaw = status.rawValue
        self.payload = payload
        self.dedupeKey = dedupeKey
        self.accountKey = accountKey
        self.createdAt = createdAt
        self.attemptCount = 0
        self.generationID = generationID
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
