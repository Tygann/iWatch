//// EpisodeProgress.swift
//import Foundation
//import SwiftData
//
//@Model
//final class EpisodeProgress {
//    @Attribute(.unique) var episodeId: Int      // Use TMDB episode id as the canonical key
//    var showId: Int
//    var seasonNumber: Int
//    var episodeNumber: Int
//    var watched: Bool
//    var progressSeconds: Int
//    var updatedAt: Date
//
//    init(episodeId: Int, showId: Int, seasonNumber: Int, episodeNumber: Int,
//         watched: Bool = false, progressSeconds: Int = 0) {
//        self.episodeId = episodeId
//        self.showId = showId
//        self.seasonNumber = seasonNumber
//        self.episodeNumber = episodeNumber
//        self.watched = watched
//        self.progressSeconds = progressSeconds
//        self.updatedAt = Date()
//    }
//}








import Foundation
import SwiftData

@Model
final class EpisodeProgress {
    @Attribute(.unique) var key: String
//    var mediaID: String // `mediaID` is MediaItem.id ("tv:123")
    var mediaID: Int
    var season: Int
    var episode: Int
    var watched: Bool
    var watchedAt: Date?

    init(mediaID: Int, season: Int, episode: Int, watched: Bool = true, watchedAt: Date? = .now) {
        self.mediaID = mediaID
        self.season = season
        self.episode = episode
        self.key = "\(mediaID)-S\(season)-E\(episode)"
        self.watched = watched
        self.watchedAt = watchedAt
    }
}
