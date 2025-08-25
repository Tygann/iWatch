// Services/API/MockData.swift
import Foundation

public final class MockData: ContentAPI {
    public init() {}

    public func search(query: String, page: Int) async throws -> [SimpleDTO] {
        return [
            SimpleDTO(id: 1, kind: .movie, title: "Mock Movie", posterPath: nil, year: 2024),
            SimpleDTO(id: 2, kind: .tv,    title: "Mock Show",  posterPath: nil, year: 2023)
        ]
    }

    public func trendingMovies(page: Int) async throws -> [SimpleDTO] {
        return (1...10).map { i in
            SimpleDTO(id: i, kind: .movie, title: "Trending Movie \(i)", posterPath: nil, year: 2024)
        }
    }

    public func trendingTV(page: Int) async throws -> [SimpleDTO] {
        return (1...10).map { i in
            SimpleDTO(id: 100 + i, kind: .tv, title: "Trending Show \(i)", posterPath: nil, year: 2023)
        }
    }

    public func movieDetails(id: Int) async throws -> MovieDetailsDTO {
        return MovieDetailsDTO(
            id: id,
            title: "Mock Movie \(id)",
            tagline: "A mock tagline",
            overview: "A mock movie overview.",
            posterPath: nil,
            backdropPath: nil,
            releaseDate: "2024-01-01",
            runtime: 110,
            genres: [GenreDTO(id: 1, name: "Action"), GenreDTO(id: 2, name: "Adventure")],
            voteAverage: 7.3,
            voteCount: 1245
        )
    }

    public func tvDetails(id: Int) async throws -> TVDetailsDTO {
        return TVDetailsDTO(
            id: id,
            name: "Mock Show \(id)",
            tagline: "A mock TV tagline",
            overview: "A mock TV overview.",
            posterPath: nil,
            backdropPath: nil,
            firstAirDate: "2023-03-14",
            episodeRunTime: [48],
            genres: [GenreDTO(id: 3, name: "Drama")],
            voteAverage: 8.1,
            voteCount: 982,
            numberOfSeasons: 3,
            numberOfEpisodes: 28,
            seasons: [
                SeasonDTO(id: 1000, name: "Season 1", seasonNumber: 1, posterPath: nil, episodeCount: 10),
                SeasonDTO(id: 1001, name: "Season 2", seasonNumber: 2, posterPath: nil, episodeCount: 9),
                SeasonDTO(id: 1002, name: "Season 3", seasonNumber: 3, posterPath: nil, episodeCount: 9)
            ]
        )
    }
    
    public func tvSeason(id: Int, seasonNumber: Int) async throws -> SeasonDetailsDTO {
        let episodes = (1...10).map { e in
            EpisodeDTO(
                id: seasonNumber * 1_000 + e,
                name: "S\(seasonNumber) • Episode \(e)",
                overview: "Mock overview for episode \(e) of season \(seasonNumber).",
                stillPath: nil,
                airDate: "2023-03-\(String(format: "%02d", min(28, e)))",
                runtime: 48,
                seasonNumber: seasonNumber,
                episodeNumber: e
            )
        }

        return SeasonDetailsDTO(
            id: seasonNumber * 10,
            name: "Season \(seasonNumber)",
            seasonNumber: seasonNumber,
            posterPath: nil,
            episodes: episodes
        )
    }
}
