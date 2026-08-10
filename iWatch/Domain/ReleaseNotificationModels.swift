import Foundation

nonisolated struct ReleaseNotificationSnapshot: Equatable, Sendable {
    let movies: [MovieRelease]
    let episodes: [EpisodeRelease]

    struct MovieRelease: Equatable, Sendable {
        let mediaID: MediaID
        let title: String
        let releaseDate: Date
    }

    struct EpisodeRelease: Equatable, Sendable {
        let showID: MediaID
        let episode: EpisodeRef
        let showTitle: String
        let episodeTitle: String
        let airDate: Date
        let airedAt: Date?
    }
}

nonisolated enum ReleaseNotificationTiming: String, CaseIterable, Identifiable, Sendable {
    case atRelease
    case fifteenMinutesBefore
    case morningOf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .atRelease: "At Release Time"
        case .fifteenMinutesBefore: "15 Minutes Before"
        case .morningOf: "Morning Of"
        }
    }
}

nonisolated struct ScheduledReleaseNotification: Equatable, Sendable {
    enum Destination: Equatable, Sendable {
        case media(MediaID)
        case episode(EpisodeRef)
    }

    let identifier: String
    let title: String
    let body: String
    let fireDate: Date
    let destination: Destination
}

nonisolated enum ReleaseNotificationPolicy {
    static let maximumScheduledCount = 48
    static let defaultMorningHour = 9

    static func notifications(
        from snapshot: ReleaseNotificationSnapshot,
        episodesEnabled: Bool,
        moviesEnabled: Bool,
        timing: ReleaseNotificationTiming,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ScheduledReleaseNotification] {
        var notifications: [ScheduledReleaseNotification] = []

        if moviesEnabled {
            notifications += snapshot.movies.compactMap { movie in
                let fireDate = morning(of: movie.releaseDate, calendar: calendar)
                guard fireDate > now else { return nil }
                return ScheduledReleaseNotification(
                    identifier: "release.movie.\(movie.mediaID.tmdbID)",
                    title: "\(movie.title) is out today",
                    body: "A movie from your Watchlist releases today.",
                    fireDate: fireDate,
                    destination: .media(movie.mediaID)
                )
            }
        }

        if episodesEnabled {
            notifications += snapshot.episodes.compactMap { episode in
                let fireDate = episodeFireDate(
                    airDate: episode.airDate,
                    airedAt: episode.airedAt,
                    timing: timing,
                    calendar: calendar
                )
                guard fireDate > now else { return nil }

                let label = "S\(episode.episode.season) E\(episode.episode.episode)"
                let releaseDescription: String
                if let airedAt = episode.airedAt, timing != .morningOf {
                    releaseDescription = "airs \(airedAt.formatted(date: .omitted, time: .shortened))"
                } else {
                    releaseDescription = "airs today"
                }
                let episodeName = episode.episodeTitle.isEmpty ? label : "\(label) “\(episode.episodeTitle)”"

                return ScheduledReleaseNotification(
                    identifier: "release.episode.\(episode.episode.showId).\(episode.episode.season).\(episode.episode.episode)",
                    title: episode.showTitle,
                    body: "\(episodeName) \(releaseDescription).",
                    fireDate: fireDate,
                    destination: .episode(episode.episode)
                )
            }
        }

        return notifications
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(maximumScheduledCount)
            .map { $0 }
    }

    private static func episodeFireDate(
        airDate: Date,
        airedAt: Date?,
        timing: ReleaseNotificationTiming,
        calendar: Calendar
    ) -> Date {
        guard let airedAt else { return morning(of: airDate, calendar: calendar) }
        switch timing {
        case .atRelease:
            return airedAt
        case .fifteenMinutesBefore:
            return airedAt.addingTimeInterval(-15 * 60)
        case .morningOf:
            return morning(of: airedAt, calendar: calendar)
        }
    }

    private static func morning(of date: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: defaultMorningHour, minute: 0, second: 0, of: date)
            ?? calendar.startOfDay(for: date).addingTimeInterval(TimeInterval(defaultMorningHour * 60 * 60))
    }
}
