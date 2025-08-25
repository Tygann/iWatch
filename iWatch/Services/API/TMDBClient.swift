// Services/API/TMDBClient.swift
import Foundation

public final class TMDBClient: ContentAPI {
    private let apiKey: String
    private let session: URLSession = .shared
    private let base = URL(string: "https://api.themoviedb.org/3")!

    public init(apiKey: String) { self.apiKey = apiKey }

    // MARK: - Public API
    public func search(query: String, page: Int) async throws -> [SimpleDTO] {
        let resp: PagedResponse<SearchResultDTO> = try await get(
            "search/multi",
            queryItems: [("query", query), ("page", String(page))]
        )

        return resp.results.compactMap { r in
            let path = r.posterPath ?? r.backdropPath
            switch r.mediaType ?? .movie {
            case .movie:
                return .init(
                    id: r.id,
                    kind: .movie,
                    title: r.title,
                    posterPath: path,
                    year: r.year,
                    genreIDs: r.genreIDs         // ✅ pass through
                )
            case .tv:
                return .init(
                    id: r.id,
                    kind: .tv,
                    title: r.title,
                    posterPath: path,
                    year: r.year,
                    genreIDs: r.genreIDs         // ✅ pass through
                )
            }
        }
    }

    public func trendingMovies(page: Int) async throws -> [SimpleDTO] {
        let resp: PagedResponse<SearchResultDTO> = try await get(
            "trending/movie/week",
            queryItems: [("page", String(page))]
        )

        return resp.results.map {
            .init(
                id: $0.id,
                kind: .movie,
                title: $0.title,
                posterPath: $0.posterPath ?? $0.backdropPath,
                year: $0.year,
                genreIDs: $0.genreIDs            // ✅ pass through
            )
        }
    }

    public func trendingTV(page: Int) async throws -> [SimpleDTO] {
        let resp: PagedResponse<SearchResultDTO> = try await get(
            "trending/tv/week",
            queryItems: [("page", String(page))]
        )

        return resp.results.map {
            .init(
                id: $0.id,
                kind: .tv,
                title: $0.title,
                posterPath: $0.posterPath ?? $0.backdropPath,
                year: $0.year,
                genreIDs: $0.genreIDs            // ✅ pass through
            )
        }
    }

    public func movieDetails(id: Int) async throws -> MovieDetailsDTO {
        try await get("movie/\(id)")
    }

    public func tvDetails(id: Int) async throws -> TVDetailsDTO {
        try await get("tv/\(id)")
    }
    
    public func tvSeason(id: Int, seasonNumber: Int) async throws -> SeasonDetailsDTO {
        try await get("tv/\(id)/season/\(seasonNumber)")
    }

    // MARK: - Core request
    private func get<T: Decodable>(_ path: String,
                                   queryItems: [(String,String)] = []) async throws -> T {
        var url = base
        for seg in path.split(separator: "/") { url.appendPathComponent(String(seg)) }

        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "api_key", value: apiKey)]
        items.append(contentsOf: queryItems.map { URLQueryItem(name: $0.0, value: $0.1) })
        comps.queryItems = items

        let (data, resp) = try await session.data(from: comps.url!)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            #if DEBUG
            if let http = resp as? HTTPURLResponse {
                print("TMDB \(path) failed: \(http.statusCode)")
                if let s = String(data: data, encoding: .utf8) { print(s) }
            }
            #endif
            throw URLError(.badServerResponse)
        }

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .useDefaultKeys
        return try dec.decode(T.self, from: data)
    }
}
