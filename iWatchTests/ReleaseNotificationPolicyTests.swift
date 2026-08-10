import Foundation
import SwiftData
import Testing
@testable import iWatch

@MainActor
struct ReleaseNotificationPolicyTests {
    @Test
    func exactAirtimeSupportsAtReleaseAndAdvanceReminder() {
        let calendar = utcCalendar
        let airedAt = date(2026, 8, 12, 20, 0, calendar: calendar)
        let snapshot = ReleaseNotificationSnapshot(
            movies: [],
            episodes: [episode(airDate: airedAt, airedAt: airedAt)]
        )

        let atRelease = ReleaseNotificationPolicy.notifications(
            from: snapshot,
            episodesEnabled: true,
            moviesEnabled: false,
            timing: .atRelease,
            now: date(2026, 8, 10, 12, 0, calendar: calendar),
            calendar: calendar
        )
        let early = ReleaseNotificationPolicy.notifications(
            from: snapshot,
            episodesEnabled: true,
            moviesEnabled: false,
            timing: .fifteenMinutesBefore,
            now: date(2026, 8, 10, 12, 0, calendar: calendar),
            calendar: calendar
        )

        #expect(atRelease.first?.fireDate == airedAt)
        #expect(early.first?.fireDate == airedAt.addingTimeInterval(-15 * 60))
        #expect(early.first?.body.contains("airs") == true)
    }

    @Test
    func dateOnlyEpisodesAndMoviesUseMorningOfRelease() {
        let calendar = utcCalendar
        let releaseDate = date(2026, 8, 12, 0, 0, calendar: calendar)
        let snapshot = ReleaseNotificationSnapshot(
            movies: [.init(
                mediaID: MediaID(kind: .movie, id: 42),
                title: "Example Movie",
                releaseDate: releaseDate
            )],
            episodes: [episode(airDate: releaseDate, airedAt: nil)]
        )

        let notifications = ReleaseNotificationPolicy.notifications(
            from: snapshot,
            episodesEnabled: true,
            moviesEnabled: true,
            timing: .atRelease,
            now: date(2026, 8, 10, 12, 0, calendar: calendar),
            calendar: calendar
        )

        #expect(notifications.count == 2)
        #expect(notifications.allSatisfy {
            calendar.component(.hour, from: $0.fireDate) == ReleaseNotificationPolicy.defaultMorningHour
        })
    }

    @Test
    func excludesPastAndDisabledReleaseTypes() {
        let calendar = utcCalendar
        let now = date(2026, 8, 10, 12, 0, calendar: calendar)
        let snapshot = ReleaseNotificationSnapshot(
            movies: [.init(
                mediaID: MediaID(kind: .movie, id: 42),
                title: "Example Movie",
                releaseDate: date(2026, 8, 12, 0, 0, calendar: calendar)
            )],
            episodes: [episode(
                airDate: date(2026, 8, 9, 0, 0, calendar: calendar),
                airedAt: nil
            )]
        )

        let notifications = ReleaseNotificationPolicy.notifications(
            from: snapshot,
            episodesEnabled: true,
            moviesEnabled: false,
            timing: .atRelease,
            now: now,
            calendar: calendar
        )

        #expect(notifications.isEmpty)
    }

    @Test
    func snapshotIncludesOnlyEligibleLibraryReleases() async throws {
        let persistence = Persistence(
            inMemory: true,
            cloudKitDatabase: ModelConfiguration.CloudKitDatabase.none
        )
        let context = persistence.makeContext()
        let future = Date.now.addingTimeInterval(2 * 24 * 60 * 60)
        let movieID = MediaID(kind: .movie, id: 42)
        let activeShowID = MediaID(kind: .show, id: 7)
        let stoppedShowID = MediaID(kind: .show, id: 8)

        context.insert(WatchlistRecord(mediaID: movieID, isInWatchlist: true))
        context.insert(WatchlistRecord(mediaID: activeShowID, isInWatchlist: true))
        context.insert(WatchlistRecord(mediaID: stoppedShowID, isInWatchlist: true))
        context.insert(MediaRecord(kind: .movie, tmdbID: 42, title: "Movie", releaseDate: future))
        context.insert(MediaRecord(kind: .show, tmdbID: 7, title: "Active Show"))
        context.insert(MediaRecord(kind: .show, tmdbID: 8, title: "Stopped Show"))
        context.insert(EpisodeRecord(
            showTMDbID: 7,
            tmdbID: 701,
            seasonNumber: 1,
            episodeNumber: 1,
            name: "Upcoming",
            airDate: future
        ))
        context.insert(EpisodeRecord(
            showTMDbID: 7,
            tmdbID: 702,
            seasonNumber: 1,
            episodeNumber: 2,
            name: "Already Watched",
            airDate: future
        ))
        context.insert(EpisodeRecord(
            showTMDbID: 8,
            tmdbID: 801,
            seasonNumber: 1,
            episodeNumber: 1,
            name: "Stopped",
            airDate: future
        ))
        context.insert(ShowDispositionRecord(showID: stoppedShowID, disposition: .stopped))
        context.insert(WatchedEventRecord(
            kind: .episode,
            tmdbID: 702,
            showTMDbID: 7,
            seasonNumber: 1,
            episodeNumber: 2,
            watchedAt: .now
        ))
        try context.save()

        let snapshot = try await LibrarySnapshotReader(persistence: persistence)
            .releaseNotificationSnapshot()

        #expect(snapshot.movies.map(\.mediaID) == [movieID])
        #expect(snapshot.episodes.map(\.episode.tmdbID) == [701])
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private func episode(airDate: Date, airedAt: Date?) -> ReleaseNotificationSnapshot.EpisodeRelease {
        .init(
            showID: MediaID(kind: .show, id: 7),
            episode: EpisodeRef(showId: 7, season: 3, episode: 8, tmdbID: 99),
            showTitle: "Example Show",
            episodeTitle: "The Release",
            airDate: airDate,
            airedAt: airedAt
        )
    }
}
