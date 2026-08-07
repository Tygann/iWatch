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

struct MediaSupplementaryDetails: Equatable, Sendable {
    struct Credit: Equatable, Identifiable, Sendable {
        let id: Int
        let name: String
        let subtitle: String?
        let profilePath: String?
        let order: Int?
    }

    struct WatchProvider: Equatable, Identifiable, Sendable {
        let id: Int
        let name: String
        let logoPath: String?
    }

    struct WatchAvailability: Equatable, Sendable {
        let link: URL?
        let stream: [WatchProvider]
        let rent: [WatchProvider]
        let buy: [WatchProvider]
    }

    struct Video: Equatable, Identifiable, Sendable {
        let id: String
        let name: String
        let key: String
        let site: String
        let type: String
        let official: Bool

        var destinationURL: URL? {
            guard site.caseInsensitiveCompare("YouTube") == .orderedSame else { return nil }
            return URL(string: "https://www.youtube.com/watch?v=\(key)")
        }
    }

    let credits: [Credit]
    let watchAvailability: WatchAvailability?
    let certification: String?
    let videos: [Video]

    var trailer: Video? {
        videos.first {
            $0.type.caseInsensitiveCompare("Trailer") == .orderedSame && $0.official && $0.destinationURL != nil
        } ?? videos.first {
            $0.type.caseInsensitiveCompare("Trailer") == .orderedSame && $0.destinationURL != nil
        }
    }
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
    let knownFor: [SearchItem]
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

enum ShowDisposition: String, Codable, Equatable, Sendable {
    case active
    case stopped
}

enum MovieLifecycle: Equatable, Sendable {
    case available
    case watchlisted
    case watched(playCount: Int, lastWatchedAt: Date)
}

enum ShowLifecycle: Equatable, Sendable {
    case available
    case watchlisted
    case watching
    case caughtUp
    case completed
    case stopped
}

struct WatchHistoryItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let mediaID: MediaID
    let showID: MediaID?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let watchedAt: Date
}

struct LibraryMovieItem: Identifiable, Equatable, Sendable {
    let mediaID: MediaID
    let title: String
    let posterPath: String?
    let releaseDate: Date?
    let listedAt: Date?
    let isInWatchlist: Bool
    let playCount: Int
    let lastWatchedAt: Date?

    var id: Int { mediaID.id }

    var isWatched: Bool { playCount > 0 }

    var lifecycle: MovieLifecycle {
        if isInWatchlist { return .watchlisted }
        if let lastWatchedAt, playCount > 0 {
            return .watched(playCount: playCount, lastWatchedAt: lastWatchedAt)
        }
        return .available
    }
}

struct LibraryShowItem: Identifiable, Equatable, Sendable {
    let mediaID: MediaID
    let title: String
    let posterPath: String?
    let status: ShowStatusSnapshot
    let progress: ShowProgress
    let isInWatchlist: Bool
    let disposition: ShowDisposition
    let listedAt: Date?
    let lastWatchedAt: Date?
    let needsProgressEnrichment: Bool

    var id: Int { mediaID.id }

    var lifecycle: ShowLifecycle {
        if disposition == .stopped { return .stopped }
        if progress.watchedCount == 0 {
            return isInWatchlist ? .watchlisted : .available
        }
        if status.bucket == .ended && progress.isComplete { return .completed }
        if progress.remainingReleased == 0 { return .caughtUp }
        return .watching
    }
}

struct ShowLibrarySnapshot: Equatable, Sendable {
    let all: [LibraryShowItem]
    let continueWatching: [LibraryShowItem]
    let comingUp: [LibraryShowItem]
    let watchlist: [LibraryShowItem]
    let caughtUp: [LibraryShowItem]
    let completed: [LibraryShowItem]

    static let empty = ShowLibrarySnapshot(items: [])

    init(items: [LibraryShowItem], referenceDate: Date = .now, calendar: Calendar = .current) {
        all = items
        continueWatching = items
            .filter { $0.lifecycle == .watching }
            .sorted {
                ($0.lastWatchedAt ?? .distantPast) > ($1.lastWatchedAt ?? .distantPast)
            }
        let startOfToday = calendar.startOfDay(for: referenceDate)
        comingUp = items
            .filter {
                guard $0.disposition == .active else { return false }
                guard let nextAirDate = $0.status.nextAirDate else { return false }
                return calendar.startOfDay(for: nextAirDate) >= startOfToday
            }
            .sorted {
                ($0.status.nextAirDate ?? .distantFuture) <
                    ($1.status.nextAirDate ?? .distantFuture)
            }
        watchlist = items
            .filter { $0.lifecycle == .watchlisted }
            .sorted { ($0.listedAt ?? .distantPast) > ($1.listedAt ?? .distantPast) }
        completed = items
            .filter { $0.lifecycle == .completed }
            .sorted { ($0.lastWatchedAt ?? .distantPast) > ($1.lastWatchedAt ?? .distantPast) }
        let completedIDs = Set(completed.map(\.id))
        caughtUp = items
            .filter {
                $0.lifecycle == .caughtUp &&
                    !completedIDs.contains($0.id)
            }
            .sorted {
                let lhsAirDate = $0.status.nextAirDate ?? .distantFuture
                let rhsAirDate = $1.status.nextAirDate ?? .distantFuture
                if lhsAirDate != rhsAirDate { return lhsAirDate < rhsAirDate }
                return ($0.lastWatchedAt ?? .distantPast) > ($1.lastWatchedAt ?? .distantPast)
            }
    }
}
