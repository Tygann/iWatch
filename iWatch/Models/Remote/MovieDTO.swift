import Foundation

public struct MovieDetailsDTO: Codable {
    public let id: Int
    public let title: String
    public let tagline: String?
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let releaseDate: String?
    public let runtime: Int?
    public let genres: [GenreDTO]
    public let voteAverage: Double?
    public let voteCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, tagline, overview, genres
        case posterPath   = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate  = "release_date"
        case runtime
        case voteAverage  = "vote_average"
        case voteCount    = "vote_count"
    }
}
