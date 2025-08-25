import Foundation

public struct TVDetailsDTO: Codable {
    public let id: Int
    public let name: String
    public let tagline: String?
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let firstAirDate: String?
    public let episodeRunTime: [Int]?
    public let genres: [GenreDTO]
    public let voteAverage: Double?
    public let voteCount: Int?
    public let numberOfSeasons: Int?
    public let numberOfEpisodes: Int?
    public let seasons: [SeasonDTO]?

    enum CodingKeys: String, CodingKey {
        case id, name, tagline, overview, genres, seasons
        case posterPath       = "poster_path"
        case backdropPath     = "backdrop_path"
        case firstAirDate     = "first_air_date"
        case episodeRunTime   = "episode_run_time"
        case voteAverage      = "vote_average"
        case voteCount        = "vote_count"
        case numberOfSeasons  = "number_of_seasons"
        case numberOfEpisodes = "number_of_episodes"
    }
}
