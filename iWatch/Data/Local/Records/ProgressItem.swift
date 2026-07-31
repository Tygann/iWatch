import Foundation
import SwiftData

@Model
final class WatchedEventRecord {
    // CloudKit-backed SwiftData cannot enforce unique constraints, so repositories
    // treat this as the logical identity for manual upserts and dedupe.
    var eventKey: String = ""
    var generationID: String = ""

    var recordID: UUID = UUID()
    var kindRaw: String = MediaKind.movie.rawValue
    var tmdbID: Int = 0
    var traktID: Int?
    var showTMDbID: Int?
    var showTraktID: Int?
    var seasonNumber: Int?
    var episodeNumber: Int?
    var watchedAt: Date = Date.distantPast
    var traktHistoryID: Int?
    var dirty: Bool = false
    var tombstoned: Bool = false
    var createdAt: Date = Date.distantPast
    var updatedAt: Date = Date.distantPast

    init(kind: MediaKind,
         tmdbID: Int,
         traktID: Int? = nil,
         showTMDbID: Int? = nil,
         showTraktID: Int? = nil,
         seasonNumber: Int? = nil,
         episodeNumber: Int? = nil,
         watchedAt: Date,
         traktHistoryID: Int? = nil,
         dirty: Bool = false,
         tombstoned: Bool = false,
         createdAt: Date = .now,
         updatedAt: Date = .now,
         generationID: String = "") {
        self.eventKey = Self.makeEventKey(kind: kind, tmdbID: tmdbID, traktID: traktID, watchedAt: watchedAt)
        self.recordID = UUID()
        self.kindRaw = kind.rawValue
        self.tmdbID = tmdbID
        self.traktID = traktID
        self.showTMDbID = showTMDbID
        self.showTraktID = showTraktID
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.watchedAt = watchedAt
        self.traktHistoryID = traktHistoryID
        self.dirty = dirty
        self.tombstoned = tombstoned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.generationID = generationID
    }

    var mediaID: MediaID {
        MediaID(kind: MediaKind(rawValue: kindRaw) ?? .movie, id: tmdbID, traktID: traktID)
    }

    static func makeEventKey(kind: MediaKind, tmdbID: Int, traktID: Int?, watchedAt: Date) -> String {
        let stamp = ISO8601DateFormatter.iWatch.string(from: watchedAt)
        return "\(kind.rawValue):tmdb:\(tmdbID):\(stamp)"
    }
}
