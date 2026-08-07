import Foundation

final class TMDbService {
    private let api: APIClient
    private let apiKey: String
    private let base = URL(string: "https://api.themoviedb.org/3")!

    init(apiClient: APIClient, apiKey: String) {
        self.api = apiClient
        self.apiKey = apiKey
    }

    // MARK: - Routes
    private func route(_ path: String, query: [URLQueryItem] = []) -> APIRoute {
        var q = query
        q.append(.init(name: "api_key", value: apiKey))
        return APIRoute(baseURL: base, path: path, query: q)
    }

    // MARK: - Movie
    func movieDetails(id: Int) async throws -> TMDbMovieDetailsDTO {
        try await api.fetch(route("/movie/\(id)"), as: TMDbMovieDetailsDTO.self)
    }

    // MARK: - TV
    func showDetails(id: Int) async throws -> TMDbShowDetailsDTO {
        try await api.fetch(route("/tv/\(id)"), as: TMDbShowDetailsDTO.self)
    }

    func supplementaryDetails(for id: MediaID, regionCode: String) async throws -> MediaSupplementaryDetails {
        let path: String
        let append: String
        switch id.kind {
        case .movie:
            path = "/movie/\(id.tmdbID)"
            append = "credits,videos,watch/providers,release_dates"
        case .show:
            path = "/tv/\(id.tmdbID)"
            append = "credits,videos,watch/providers,content_ratings"
        default:
            throw AppError.featureNotImplemented("Supplementary details are only available for movies and shows.")
        }

        let dto = try await api.fetch(
            route(path, query: [.init(name: "append_to_response", value: append)]),
            as: TMDbMediaSupplementaryDTO.self
        )
        return TMDbMappers.supplementary(dto, kind: id.kind, regionCode: regionCode)
    }

    /// Raw season payload (you can keep this if needed elsewhere)
    func seasonDetails(showId: Int, seasonNumber: Int) async throws -> Data {
        try await api.data(route("/tv/\(showId)/season/\(seasonNumber)"))
    }

    /// Domain-friendly: mapped episodes for a season
    func seasonEpisodes(showId: Int, seasonNumber: Int) async throws -> [EpisodeDetails] {
        let data = try await seasonDetails(showId: showId, seasonNumber: seasonNumber)
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        dec.dateDecodingStrategy = .formatted(DateFormatters.tmdbYMD)
        let dto = try dec.decode(TMDbSeasonDetailsDTO.self, from: data)
        return dto.episodes.map { TMDbMappers.episode($0, showId: showId) }
    }

    /// Episodes
    func episodeDetails(showId: Int, seasonNumber: Int, episodeNumber: Int) async throws -> EpisodeDetails {
        let append = URLQueryItem(name: "append_to_response", value: "credits,images,videos,external_ids")
        let data = try await api.data(
            route("/tv/\(showId)/season/\(seasonNumber)/episode/\(episodeNumber)", query: [append])
        )

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        dec.dateDecodingStrategy = .formatted(DateFormatters.tmdbYMD)

        let dto = try dec.decode(TMDbEpisodeDTO.self, from: data)
        return TMDbMappers.episode(dto, showId: showId)
    }

    // MARK: - Person (with combined credits)
    func personDetails(id: Int) async throws -> TMDbPersonDetailsDTO {
        let append = URLQueryItem(name: "append_to_response", value: "combined_credits")
        return try await api.fetch(route("/person/\(id)", query: [append]), as: TMDbPersonDetailsDTO.self)
    }

    func search(query: String, page: Int = 1) async throws -> [SearchItem] {
        let q: [URLQueryItem] = [
            .init(name: "query", value: query),
            .init(name: "page", value: String(page)),
            .init(name: "include_adult", value: "false")
        ]
        let pageDTO = try await api.fetch(route("/search/multi", query: q), as: TMDbMultiSearchPageDTO.self)
        return pageDTO.results.compactMap(TMDbMappers.searchItem(_:))
    }

    func trending(kind: MediaKind, timeWindow: String = "day") async throws -> [SearchItem] {
        let pageDTO: TMDbTrendingPageDTO
        switch kind {
        case .movie:
            pageDTO = try await api.fetch(route("/trending/movie/\(timeWindow)"), as: TMDbTrendingPageDTO.self)
        case .show:
            pageDTO = try await api.fetch(route("/trending/tv/\(timeWindow)"), as: TMDbTrendingPageDTO.self)
        case .episode:
            return []
        case .person:
            return []
        }
        return pageDTO.results.map { TMDbMappers.trendingItem($0, kind: kind) }
    }

    func mixedTrending(timeWindow: String = "day") async throws -> [SearchItem] {
        let page = try await api.fetch(
            route("/trending/all/\(timeWindow)"),
            as: TMDbTrendingPageDTO.self
        )
        return page.results.compactMap(TMDbMappers.mixedTrendingItem(_:))
    }

    func discovery(kind: MediaKind, collection: DiscoveryCollection) async throws -> [SearchItem] {
        if collection == .trending {
            return try await trending(kind: kind)
        }

        let path: String
        switch (kind, collection) {
        case (.movie, .popular): path = "/movie/popular"
        case (.movie, .topRated): path = "/movie/top_rated"
        case (.movie, .nowPlaying): path = "/movie/now_playing"
        case (.movie, .upcoming): path = "/movie/upcoming"
        case (.show, .popular): path = "/tv/popular"
        case (.show, .topRated): path = "/tv/top_rated"
        case (.show, .airingThisWeek): path = "/tv/on_the_air"
        default: return []
        }

        let page = try await api.fetch(route(path), as: TMDbTrendingPageDTO.self)
        return page.results.map { TMDbMappers.trendingItem($0, kind: kind) }
    }

    func watchProviders(kind: MediaKind, regionCode: String) async throws -> [DiscoveryProvider] {
        let mediaPath = kind == .movie ? "movie" : "tv"
        let page = try await api.fetch(
            route("/watch/providers/\(mediaPath)", query: [
                .init(name: "watch_region", value: regionCode.uppercased())
            ]),
            as: TMDbWatchProviderPageDTO.self
        )
        return page.results
            .map {
                DiscoveryProvider(
                    id: $0.providerId,
                    name: $0.providerName,
                    logoPath: $0.logoPath,
                    displayPriority: $0.displayPriority ?? .max
                )
            }
            .sorted {
                if $0.displayPriority == $1.displayPriority { return $0.name < $1.name }
                return $0.displayPriority < $1.displayPriority
            }
    }

    func watchProviders(regionCode: String) async throws -> [DiscoveryProvider] {
        async let movieProviders = watchProviders(kind: .movie, regionCode: regionCode)
        async let showProviders = watchProviders(kind: .show, regionCode: regionCode)

        let (movies, shows) = try await (movieProviders, showProviders)
        let combined = movies + shows
        return Dictionary(grouping: combined, by: \.id)
            .compactMap { _, providers in
                providers.min {
                    if $0.displayPriority == $1.displayPriority { return $0.name < $1.name }
                    return $0.displayPriority < $1.displayPriority
                }
            }
            .sorted {
                if $0.displayPriority == $1.displayPriority { return $0.name < $1.name }
                return $0.displayPriority < $1.displayPriority
            }
    }

    func discover(
        kind: MediaKind,
        providerID: Int,
        offerType: ProviderOfferType,
        regionCode: String
    ) async throws -> [SearchItem] {
        let mediaPath = kind == .movie ? "movie" : "tv"
        let page = try await api.fetch(
            route("/discover/\(mediaPath)", query: [
                .init(name: "include_adult", value: "false"),
                .init(name: "sort_by", value: "popularity.desc"),
                .init(name: "watch_region", value: regionCode.uppercased()),
                .init(name: "with_watch_monetization_types", value: offerType.tmdbValue),
                .init(name: "with_watch_providers", value: String(providerID))
            ]),
            as: TMDbTrendingPageDTO.self
        )
        return page.results.map { TMDbMappers.trendingItem($0, kind: kind) }
    }
}

typealias TMDbClient = TMDbService
