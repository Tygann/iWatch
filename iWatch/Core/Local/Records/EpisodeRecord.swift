import Foundation
import SwiftData

@Model
final class EpisodeRecord {
    // CloudKit-backed SwiftData cannot enforce unique constraints, so repositories
    // treat this as the logical identity for manual upserts and dedupe.
    var episodeKey: String = ""

    var showTMDbID: Int = 0
    var showTraktID: Int?
    var tmdbID: Int = 0
    var traktID: Int?
    var seasonNumber: Int = 0
    var episodeNumber: Int = 0
    var name: String = ""
    var airDate: Date?
    var stillPath: String?
    var overview: String?
    var extrasData: Data?
    var updatedAt: Date = Date.distantPast

    init(showTMDbID: Int,
         showTraktID: Int? = nil,
         tmdbID: Int,
         traktID: Int? = nil,
         seasonNumber: Int,
         episodeNumber: Int,
         name: String,
         airDate: Date? = nil,
         stillPath: String? = nil,
         overview: String? = nil,
         extrasData: Data? = nil,
         updatedAt: Date = .now) {
        self.episodeKey = "ep:\(showTMDbID):S\(seasonNumber):E\(episodeNumber)"
        self.showTMDbID = showTMDbID
        self.showTraktID = showTraktID
        self.tmdbID = tmdbID
        self.traktID = traktID
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.name = name
        self.airDate = airDate
        self.stillPath = stillPath
        self.overview = overview
        self.extrasData = extrasData
        self.updatedAt = updatedAt
    }
}
