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
        let checked = try persistence.makeMetadataContext(now: now)
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
        let checked = try persistence.makeMetadataContext(now: now)
        #expect(try checked.fetchCount(FetchDescriptor<MediaRecord>()) == 0)
    }
}
