import Foundation
import SwiftData

@Model
final class MediaRecord {
    // CloudKit-backed SwiftData cannot enforce unique constraints, so repositories
    // treat this as the logical identity for manual upserts and dedupe.
    var mediaKey: String = ""

    var kindRaw: String = MediaKind.movie.rawValue
    var tmdbID: Int = 0
    var traktID: Int?

    var title: String = ""
    var overview: String?
    var tagline: String?
    var posterPath: String?
    var backdropPath: String?
    var rating: Double?
    var ratingCount: Int?
    var genres: [String] = []
    var releaseDate: Date?
    var runtimeMinutes: Int?
    var totalEpisodes: Int?
    var nextAirDate: Date?
    var statusRaw: String?
    var seasonsData: Data?
    var updatedAt: Date = Date.distantPast

    init(kind: MediaKind,
         tmdbID: Int,
         traktID: Int? = nil,
         title: String,
         overview: String? = nil,
         tagline: String? = nil,
         posterPath: String? = nil,
         backdropPath: String? = nil,
         rating: Double? = nil,
         ratingCount: Int? = nil,
         genres: [String] = [],
         releaseDate: Date? = nil,
         runtimeMinutes: Int? = nil,
         totalEpisodes: Int? = nil,
         nextAirDate: Date? = nil,
         statusRaw: String? = nil,
         seasonsData: Data? = nil,
         updatedAt: Date = .now) {
        self.mediaKey = "\(kind.rawValue):\(tmdbID)"
        self.kindRaw = kind.rawValue
        self.tmdbID = tmdbID
        self.traktID = traktID
        self.title = title
        self.overview = overview
        self.tagline = tagline
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.rating = rating
        self.ratingCount = ratingCount
        self.genres = genres
        self.releaseDate = releaseDate
        self.runtimeMinutes = runtimeMinutes
        self.totalEpisodes = totalEpisodes
        self.nextAirDate = nextAirDate
        self.statusRaw = statusRaw
        self.seasonsData = seasonsData
        self.updatedAt = updatedAt
    }

    var kind: MediaKind {
        MediaKind(rawValue: kindRaw) ?? .movie
    }
}
