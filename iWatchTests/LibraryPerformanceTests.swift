import Foundation
import SwiftData
import XCTest
@testable import iWatch

@MainActor
final class LibraryPerformanceTests: XCTestCase {
    func testRepresentativeLibrarySnapshotBaseline() async throws {
        // Synthetic scale from the tester-visible library counts, never the live store.
        let persistence = Persistence(inMemory: true, cloudKitDatabase: ModelConfiguration.CloudKitDatabase.none)
        let context = persistence.makeContext()
        for movie in 1...49 {
            context.insert(MediaRecord(kind: .movie, tmdbID: movie, title: "Fixture Movie \(movie)"))
            context.insert(WatchlistRecord(mediaID: MediaID(kind: .movie, id: movie), isInWatchlist: true))
        }
        for show in 1...32 {
            context.insert(MediaRecord(kind: .show, tmdbID: show, title: "Fixture Show \(show)"))
            context.insert(WatchlistRecord(mediaID: MediaID(kind: .show, id: show), isInWatchlist: true))
            for episode in 1...20 {
                context.insert(EpisodeRecord(showTMDbID: show, tmdbID: show * 1000 + episode,
                    seasonNumber: 1, episodeNumber: episode, name: "Fixture Episode",
                    airDate: Date(timeIntervalSince1970: 1600000000)))
            }
        }
        for index in 0..<5105 {
            let date = Date(timeIntervalSince1970: 1600000000 + Double(index * 3600))
            if index % 5 == 0 {
                context.insert(WatchedEventRecord(kind: .movie, tmdbID: index % 49 + 1, watchedAt: date, traktHistoryID: index + 1))
            } else {
                let show = index % 32 + 1
                let episode = (index / 32) % 20 + 1
                context.insert(WatchedEventRecord(kind: .episode, tmdbID: show * 1000 + episode,
                    showTMDbID: show, seasonNumber: 1, episodeNumber: episode, watchedAt: date, traktHistoryID: index + 1))
            }
        }
        try context.save()
        let reader = LibrarySnapshotReader(persistence: persistence)
        var movies: [Double] = []
        var shows: [Double] = []
        for _ in 0..<3 {
            let start = DispatchTime.now().uptimeNanoseconds
            let movieItems = try await reader.movieItems()
            let middle = DispatchTime.now().uptimeNanoseconds
            let showItems = try await reader.showItems()
            let end = DispatchTime.now().uptimeNanoseconds
            XCTAssertEqual(movieItems.count, 49)
            XCTAssertEqual(showItems.count, 32)
            movies.append(Double(middle - start) / 1_000_000)
            shows.append(Double(end - middle) / 1_000_000)
        }
        let summary = "IWATCH_PERF synthetic history=5105 movies=49 shows=32 episodes=640 runs=3 movie_ms=\(movies) show_ms=\(shows)"
        print(summary)
        let attachment = XCTAttachment(string: summary)
        attachment.name = "Library snapshot baseline"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
