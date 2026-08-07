import Foundation

enum DiscoveryCollection: String, CaseIterable, Identifiable, Sendable {
    case trending
    case popular
    case topRated
    case nowPlaying
    case upcoming
    case airingThisWeek

    var id: String { rawValue }

    func title(for kind: MediaKind) -> String {
        switch self {
        case .trending: "Trending"
        case .popular: "Popular"
        case .topRated: "Top Rated"
        case .nowPlaying: "Now Playing"
        case .upcoming: "Upcoming"
        case .airingThisWeek: "Airing This Week"
        }
    }

    static func collections(for kind: MediaKind) -> [DiscoveryCollection] {
        switch kind {
        case .movie: [.trending, .nowPlaying, .upcoming, .popular, .topRated]
        case .show: [.trending, .airingThisWeek, .popular, .topRated]
        case .episode, .person: []
        }
    }
}

struct DiscoveryProvider: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let logoPath: String?
    let displayPriority: Int
}

enum ProviderOfferType: String, CaseIterable, Identifiable, Sendable {
    case stream
    case rent
    case buy

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var tmdbValue: String {
        switch self {
        case .stream: "flatrate|free|ads"
        case .rent: "rent"
        case .buy: "buy"
        }
    }
}
