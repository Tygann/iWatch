import Foundation
import SwiftData

@Model
final class WatchlistRecord {
    // CloudKit-backed SwiftData cannot enforce unique constraints, so repositories
    // treat this as the logical identity for manual upserts and dedupe.
    var mediaKey: String = ""

    var kindRaw: String = MediaKind.movie.rawValue
    var tmdbID: Int = 0
    var traktID: Int?
    var isInWatchlist: Bool = false
    var listedAt: Date?
    var localUpdatedAt: Date = Date.distantPast
    var remoteUpdatedAt: Date?
    var dirty: Bool = false

    init(mediaID: MediaID,
         isInWatchlist: Bool,
         listedAt: Date? = nil,
         localUpdatedAt: Date = .now,
         remoteUpdatedAt: Date? = nil,
         dirty: Bool = false) {
        self.mediaKey = mediaID.stableKey
        self.kindRaw = mediaID.kind.rawValue
        self.tmdbID = mediaID.tmdbID
        self.traktID = mediaID.traktID
        self.isInWatchlist = isInWatchlist
        self.listedAt = listedAt
        self.localUpdatedAt = localUpdatedAt
        self.remoteUpdatedAt = remoteUpdatedAt
        self.dirty = dirty
    }

    var mediaID: MediaID {
        MediaID(kind: MediaKind(rawValue: kindRaw) ?? .movie, id: tmdbID, traktID: traktID)
    }
}
