import Foundation

nonisolated struct EpisodeRef: Hashable, Codable, Identifiable, Sendable {
    let showId: Int
    let showTraktID: Int?
    let season: Int
    let episode: Int
    let tmdbID: Int?
    let traktID: Int?

    init(showId: Int,
         showTraktID: Int? = nil,
         season: Int,
         episode: Int,
         tmdbID: Int? = nil,
         traktID: Int? = nil) {
        self.showId = showId
        self.showTraktID = showTraktID
        self.season = season
        self.episode = episode
        self.tmdbID = tmdbID
        self.traktID = traktID
    }

    var id: String { key } // for Identifiable
    var key: String { "show:\(showId):S\(season)E\(episode)" } // matches your episodeKey style
}
