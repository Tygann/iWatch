import Foundation

enum EpisodeKeys {
    static func make(showId: Int, season: Int, episode: Int) -> String {
        "ep:\(showId):S\(season):E\(episode)"
    }
}
