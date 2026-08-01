import Foundation

enum MediaDetails: Equatable, Sendable {
    case movie(MovieDetails)
    case show(ShowDetails)
}

extension MediaDetails {
    var title: String          { base.title }
    var overview: String?      { base.overview }
    var tagline: String?       { base.tagline }
    var posterPath: String?    { base.posterPath }
    var backdropPath: String?  { base.backdropPath }
    var rating: Double?        { base.rating }
    var ratingCount: Int?      { base.ratingCount }
    var genres: [String]       { base.genres }
//    var releaseYear: String?   { base.releaseYear }
    var releaseDate: Date?     { base.releaseDate }

    var movieRuntimeMinutes: Int? {
        if case let .movie(m) = self { return m.runtimeMinutes }
        return nil
    }

    var showStatusDisplayName: String? {
        guard case let .show(show) = self,
              let status = show.status?.trimmingCharacters(in: .whitespacesAndNewlines),
              !status.isEmpty else {
            return nil
        }

        switch status.lowercased() {
        case "returning series":
            return "Returning"
        case "canceled", "cancelled":
            return "Canceled"
        case "ended":
            return "Ended"
        case "in production":
            return "In Production"
        case "planned":
            return "Planned"
        case "pilot":
            return "Pilot"
        default:
            return status
        }
    }

    var mediaID: MediaID {
        switch self {
        case .movie(let movie):
            return MediaID(kind: .movie, id: movie.common.id, traktID: movie.common.traktID)
        case .show(let show):
            return MediaID(kind: .show, id: show.common.id, traktID: show.common.traktID)
        }
    }

    var showSeasons: [ShowDetails.Season] {
        if case let .show(s) = self { return s.seasons }
        return []
    }

    // Return the MediaCommon directly (no tuple)
    private var base: MediaCommon {
        switch self {
        case .movie(let m): return m.common
        case .show(let s):  return s.common
        }
    }
}
