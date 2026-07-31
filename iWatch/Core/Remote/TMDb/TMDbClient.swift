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
}

typealias TMDbClient = TMDbService
