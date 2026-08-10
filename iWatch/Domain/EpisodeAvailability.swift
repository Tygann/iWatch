import Foundation

nonisolated struct EpisodeAirtime: Equatable, Sendable {
    let traktID: Int?
    let tmdbID: Int?
    let seasonNumber: Int
    let episodeNumber: Int
    let airedAt: Date?
}

nonisolated enum EpisodeAvailability {
    static func isReleased(
        airDate: Date?,
        airedAt: Date?,
        relativeTo now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        if let airedAt {
            return airedAt <= now
        }
        guard let airDate else { return false }
        return calendar.startOfDay(for: airDate) <= calendar.startOfDay(for: now)
    }
}

extension EpisodeDetails {
    func merging(airtime: EpisodeAirtime, showTraktID: Int?) -> EpisodeDetails {
        EpisodeDetails(
            id: airtime.tmdbID ?? id,
            traktID: airtime.traktID ?? traktID,
            showId: showId,
            showTraktID: showTraktID ?? self.showTraktID,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            name: name,
            airDate: airDate,
            airedAt: airtime.airedAt ?? airedAt,
            stillPath: stillPath,
            overview: overview,
            extras: extras
        )
    }
}
