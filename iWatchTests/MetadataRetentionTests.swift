import Foundation
import SwiftData
import Testing
@testable import iWatch

@MainActor
struct MetadataRetentionTests {
    @Test
    func expirationRemovesOnlyMetadataAndDoesNotRenewOnEdits() throws {
        let persistence = try Persistence(inMemory: true)
        let context = persistence.makeContext()
        let now = Date()
        let old = now.addingTimeInterval(-151 * 86400)
        let media = MediaRecord(kind: .movie, tmdbID: 10, title: "Expired", updatedAt: old)
        media.updatedAt = now // Search/sync edits cannot renew old retained fields.
        context.insert(media)
        context.insert(MediaRecord(kind: .movie, tmdbID: 20, title: "Fresh", updatedAt: now))
        context.insert(EpisodeRecord(showTMDbID: 30, tmdbID: 31, seasonNumber: 1,
            episodeNumber: 1, name: "Expired", updatedAt: old))
        context.insert(WatchlistRecord(mediaID: MediaID(kind: .movie, id: 10), isInWatchlist: true))
        context.insert(WatchedEventRecord(kind: .movie, tmdbID: 10, watchedAt: old, dirty: true))
        context.insert(SyncOperationRecord(kind: .addHistory, payload: Data(), accountKey: "account-a"))
        try context.save()
        let checked = persistence.makeContext()
        #expect(try persistence.expireProviderMetadata(in: checked, now: now))
        #expect(try checked.fetch(FetchDescriptor<MediaRecord>()).map(\.tmdbID) == [20])
        #expect(try checked.fetchCount(FetchDescriptor<EpisodeRecord>()) == 0)
        #expect(try checked.fetchCount(FetchDescriptor<WatchlistRecord>()) == 1)
        #expect(try checked.fetch(FetchDescriptor<WatchedEventRecord>()).first?.dirty == true)
        #expect(try checked.fetch(FetchDescriptor<SyncOperationRecord>()).first?.accountKey == "account-a")
    }

    @Test
    func unknownLegacyAndFutureDatesExpireAtBoundary() throws {
        let persistence = try Persistence(inMemory: true)
        let context = persistence.makeContext()
        let now = Date()
        for (id, date) in [(1, Date.distantPast), (2, now.addingTimeInterval(60)),
                           (3, now.addingTimeInterval(-150 * 86400))] {
            let record = MediaRecord(kind: .movie, tmdbID: id, title: "Untrusted")
            record.metadataCachedAt = date
            context.insert(record)
        }
        try context.save()
        let checked = persistence.makeContext()
        #expect(try persistence.expireProviderMetadata(in: checked, now: now))
        #expect(try checked.fetchCount(FetchDescriptor<MediaRecord>()) == 0)
    }

    @Test
    func libraryReadsAndEditsLeaveExpiredMetadataForMaintenance() async throws {
        let container = AppContainer.preview(seedCatalog: false)
        let context = container.persistence.makeContext()
        let movie = MediaID(kind: .movie, id: 10)
        let expired = MediaRecord(kind: .movie, tmdbID: movie.id, title: "Expired",
                                  updatedAt: Date().addingTimeInterval(-151 * 86400))
        context.insert(expired)
        try context.save()

        try await container.libraryRepository.setWatchlist(true, for: movie)
        let movies = try await container.libraryRepository.movieLibraryItems()
        #expect(movies.first?.title == "Unknown")
        #expect(try container.persistence.makeContext().fetchCount(FetchDescriptor<MediaRecord>()) == 1)
        #expect(try await container.libraryRepository.expireProviderMetadata())
        #expect(try await !container.libraryRepository.expireProviderMetadata())
    }

    @Test
    func watchlistSnapshotsResolveReplicasBeforeFilteringRemovals() async throws {
        let container = AppContainer.preview(seedCatalog: false)
        let context = container.persistence.makeContext()
        let removed = MediaID(kind: .movie, id: 10)
        let kept = MediaID(kind: .movie, id: 20)
        let now = Date()
        context.insert(WatchlistRecord(mediaID: removed, isInWatchlist: true, localUpdatedAt: now.addingTimeInterval(-60)))
        context.insert(WatchlistRecord(mediaID: removed, isInWatchlist: false, localUpdatedAt: now))
        context.insert(WatchlistRecord(mediaID: kept, isInWatchlist: true, localUpdatedAt: now.addingTimeInterval(-60)))
        context.insert(WatchlistRecord(mediaID: kept, isInWatchlist: true, localUpdatedAt: now))
        try context.save()

        #expect(await !container.libraryRepository.isInWatchlist(removed))
        let movies = try await container.libraryRepository.movieLibraryItems()
        #expect(movies.map(\.mediaID) == [kept])
    }
}
