import Foundation

struct TVDetailsDTOOrig: Decodable, Sendable {
    struct NetworkDTO: Decodable, Sendable { let name: String }
    struct SeasonStub: Decodable, Sendable {
        let season_number: Int
        let episode_count: Int?
        let name: String
        let air_date: String?
        let poster_path: String?
    }

    let id: Int
    let name: String
    let number_of_seasons: Int
    let number_of_episodes: Int
    let overview: String?
    let networks: [NetworkDTO]
    let seasons: [SeasonStub]
    
    // NEW
    let backdrop_path: String?
}

struct TVSeasonDTO: Decodable, Sendable {
    struct EpisodeDTO: Decodable, Sendable, Identifiable {
        let id: Int
        let episode_number: Int
        let season_number: Int?
        let name: String
        let overview: String?
        let air_date: String?
        let still_path: String?
    }
    let id: Int
    let season_number: Int
    let episodes: [EpisodeDTO]
}

struct TVVideosDTO: Decodable, Sendable {
    struct Video: Decodable, Sendable {
        let key: String
        let name: String
        let site: String  // "YouTube", "Vimeo", …
        let type: String  // "Trailer", "Teaser", …
    }
    let results: [Video]
}
