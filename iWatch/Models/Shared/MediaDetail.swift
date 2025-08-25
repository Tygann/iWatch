//// MediaDetail.swift
//import Foundation
//
//struct MediaDetail: Identifiable, Hashable {
//    enum Kind: String, Hashable { case movie, tv } // rename tv -> show if you like
//
//    // Common
//    let id: Int
//    let kind: Kind
//    let title: String
//    let tagline: String?
//    let overview: String?
//    let posterPath: String?
//    let backdropPath: String?
//    let releaseYear: String?
//    let runtimeMinutes: Int?
//    let genres: [String]
//    let rating: Double?
//    let voteCount: Int?
//
//    // Movie-only
//    let movieReleaseDate: String?
//
//    // Show-only
//    let numberOfSeasons: Int?
//    let numberOfEpisodes: Int?
//    let seasons: [Season]?        // <- fully populated with episodes for shows
//}
//
//extension MediaDetail {
//    struct Season: Identifiable, Hashable {
//        let id: Int
//        let name: String
//        let seasonNumber: Int
//        let posterPath: String?
//        let episodeCount: Int?
//        let episodes: [Episode]    // <- domain Episode, not view data
//    }
//
//    struct Episode: Identifiable, Hashable {
//        let id: Int                // TMDB episode id
//        let seasonNumber: Int
//        let episodeNumber: Int
//        let name: String
//        let overview: String?
//        let stillPath: String?
//        let runtimeMinutes: Int?
//        let airDate: String?
//        let rating: Double?
//        let voteCount: Int?
//    }
//}








import Foundation

struct MediaDetail: Identifiable, Hashable {
    enum Kind: String, Hashable { case movie, tv }

    // common
    let id: Int
    let kind: Kind
    let title: String
    let tagline: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseYear: String?
    let runtimeMinutes: Int?
    let genres: [String]
    let rating: Double?
    let voteCount: Int?

    // movie‑only
    let movieReleaseDate: String?

    // tv‑only
    let numberOfSeasons: Int?
    let numberOfEpisodes: Int?
    let seasons: [Season]?

    struct Season: Identifiable, Hashable {
        let id: Int
        let name: String
        let seasonNumber: Int
        let posterPath: String?
        let episodeCount: Int?
    }
}









//// Models/Shared/MediaDetail.swift
//import Foundation
//public struct MediaDetail: Equatable {
//    public let id: Int
//    public let kind: MediaRef.Kind
//    public let title: String
//    public let tagline: String?
//    public let overview: String?
//    public let posterPath: String?
//    public let backdropPath: String?
//    public let releaseYear: String?
//    public let runtimeMinutes: Int?
//    public let genres: [String]
//    public let rating: Double?
//    public let voteCount: Int?
//    public let movieReleaseDate: String?
//    public let numberOfSeasons: Int?
//    public let numberOfEpisodes: Int?
//    public let seasons: [TVSeasonLight]?
//
//    public struct TVSeasonLight: Equatable, Identifiable {
//        public let id: Int
//        public let name: String
//        public let seasonNumber: Int
//        public let posterPath: String?
//        public let episodeCount: Int?
//    }
//}





//struct MediaDetail: Equatable {
//    // Common
//    let id: Int
//    let kind: MediaItem.Kind
//    let title: String
//    let tagline: String?
//    let overview: String?
//    let posterPath: String?
//    let backdropPath: String?
//    let releaseYear: String?      // movie: releaseDate.year; tv: firstAirDate.year
//    let runtimeMinutes: Int?      // movie: runtime; tv: episodeRunTime.first
//    let genres: [String]
//    let rating: Double?           // voteAverage
//    let voteCount: Int?
//
//    // Movie-only
//    let movieReleaseDate: String?
//
//    // TV-only
//    let numberOfSeasons: Int?
//    let numberOfEpisodes: Int?
//    let seasons: [TVSeasonLight]?
//
//    struct TVSeasonLight: Equatable, Identifiable {
//        let id: Int
//        let name: String
//        let seasonNumber: Int
//        let posterPath: String?
//        let episodeCount: Int?
//    }
//}
