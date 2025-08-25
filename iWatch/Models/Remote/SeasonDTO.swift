// Models/Remote/SeasonDetailsDTO.swift
import Foundation

public struct SeasonDTO: Codable, Identifiable {
    public let id: Int
    public let name: String
    public let seasonNumber: Int
    public let posterPath: String?
    public let episodeCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case seasonNumber = "season_number"
        case posterPath   = "poster_path"
        case episodeCount = "episode_count"
    }
}

public struct SeasonDetailsDTO: Decodable {
    public let id: Int
    public let name: String
    public let seasonNumber: Int
    public let posterPath: String?
    public let episodes: [EpisodeDTO]

    enum CodingKeys: String, CodingKey {
        case id, name, episodes
        case seasonNumber = "season_number"
        case posterPath   = "poster_path"
    }
}

public struct EpisodeDTO: Decodable, Identifiable {
    public let id: Int
    public let name: String
    public let overview: String?
    public let stillPath: String?
    public let airDate: String?
    public let runtime: Int?
    public let seasonNumber: Int?
    public let episodeNumber: Int
    
    // Computed property to convert airDate string to Date
    var dateAirDate: Date? {
        guard let airDate = airDate else { return nil }
        return convertStringToDate(dateString: airDate)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, overview, runtime
        case stillPath      = "still_path"
        case airDate        = "air_date"
        case seasonNumber   = "season_number"
        case episodeNumber  = "episode_number"
    }
}

// MARK: - Helper Functions

// Helper function to convert date string to Date
func convertStringToDate(dateString: String) -> Date? {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd" // Adjust based on your date format
    return dateFormatter.date(from: dateString)
}

// Helper function to convert time string to Date
func convertStringToTime(timeString: String) -> Date? {
    let timeFormatter = DateFormatter()
    timeFormatter.dateFormat = "HH:mm:ss" // The format your time string is in
    return timeFormatter.date(from: timeString)
}
