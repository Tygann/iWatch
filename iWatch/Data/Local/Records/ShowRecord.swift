import Foundation

struct StoredShowSeason: Codable, Hashable, Sendable {
    let id: Int
    let traktID: Int?
    let seasonNumber: Int
    let name: String
    let episodeCount: Int?
    let posterPath: String?
}
