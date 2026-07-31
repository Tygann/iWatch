import Foundation

struct MediaCommon: Equatable, Sendable {
    let id: Int
    let traktID: Int?
    let title: String
    let overview: String?
    let tagline: String?
    let posterPath: String?
    let backdropPath: String?
    let rating: Double?
    let ratingCount: Int?
    let genres: [String]
    let releaseDate: Date?
}

struct MovieDetails: Equatable, Sendable {
    let common: MediaCommon
    let runtimeMinutes: Int?
}

struct ShowDetails: Equatable, Sendable {
    struct Season: Equatable, Identifiable, Sendable {
        let id: Int
        let traktID: Int?
        let seasonNumber: Int
        let name: String
        let episodeCount: Int?
        let posterPath: String?
    }
    let common: MediaCommon
    let seasons: [Season]
    let totalEpisodes: Int?
    let nextAirDate: Date?
    let status: String?
}

/// Used for both season rows and the full episode page.
/// Season fetch populates the core only; the details fetch fills `extras`.
struct EpisodeDetails: Equatable, Identifiable, Sendable {
    let id: Int                 // TMDb episode id
    let traktID: Int?
    let showId: Int
    let showTraktID: Int?
    let seasonNumber: Int
    let episodeNumber: Int
    let name: String
    let airDate: Date?
    let stillPath: String?
    let overview: String?
    var extras: Extras?

    struct Extras: Equatable, Sendable, Codable {
        struct Credit: Identifiable, Hashable, Sendable, Codable {
            let id: Int
            let name: String
            let role: String?      // character (cast/guest)
            let job: String?       // crew job (Director, Writer, etc.)
            let profilePath: String?
            let order: Int?          // NEW: TMDb “cast order” for sorting (optional)
        }
        struct ExternalIDs: Equatable, Sendable, Codable {
            let imdb: String?
            let tvdb: Int?
            let facebook: String?
            let instagram: String?
            let twitter: String?
        }
        struct Video: Identifiable, Equatable, Sendable, Codable {
            let id: String
            let key: String   // YouTube key
            let name: String
            let site: String
            let type: String
        }

        // Core “details-only” fields
        let seasonNumber: Int
        let runtime: Int?
        let voteAverage: Double?
        let voteCount: Int?
        let productionCode: String?

        // Appended blocks
        let cast: [Credit]
        let directors: [Credit]
        let writers: [Credit]
        let guestStars: [Credit]
        let crew: [Credit]           // full crew if you want to show more
        let images: [String]         // still file paths
        let videos: [Video]
        let externalIDs: ExternalIDs
    }

    var ref: EpisodeRef {
        EpisodeRef(
            showId: showId,
            showTraktID: showTraktID,
            season: seasonNumber,
            episode: episodeNumber,
            tmdbID: id,
            traktID: traktID
        )
    }

    var mediaID: MediaID {
        MediaID(kind: .episode, id: id, traktID: traktID)
    }
}

struct PersonDetails: Equatable, Sendable {
    let id: Int
    let name: String
    let biography: String?
    let profilePath: String?
    let knownFor: [MediaRef]
}

struct ShowStatusSnapshot: Equatable, Sendable {
    enum Bucket: String, Equatable, Sendable {
        case airing
        case returning
        case ended
    }

    let bucket: Bucket
    let nextAirDate: Date?
}

struct ShowProgress: Equatable, Sendable {
    struct NextEpisode: Equatable, Sendable {
        let tmdbID: Int
        let traktID: Int?
        let season: Int
        let episode: Int
        let airDate: Date?
    }

    let watchedEpisodeKeys: Set<String>
    let watchedCount: Int
    let totalEpisodes: Int?
    let remainingReleased: Int
    let nextEpisode: NextEpisode?

    var isComplete: Bool {
        remainingReleased == 0 && (totalEpisodes.map { watchedCount >= $0 } ?? false)
    }
}

struct LibraryMovieItem: Identifiable, Equatable, Sendable {
    let mediaID: MediaID
    let title: String
    let posterPath: String?
    let releaseDate: Date?
    let isWatched: Bool

    var id: Int { mediaID.id }
}

struct LibraryShowItem: Identifiable, Equatable, Sendable {
    let mediaID: MediaID
    let title: String
    let posterPath: String?
    let status: ShowStatusSnapshot
    let progress: ShowProgress

    var id: Int { mediaID.id }
}
