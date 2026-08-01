import Foundation
import SwiftData
import Testing
@testable import iWatch

@MainActor
struct FoundationRewriteTests {
    @Test
    func initialBaselineIsPullOnly() async throws {
        let persistence = makePersistence()
        let remote = FakeTraktSyncRemote(
            token: makeToken(),
            lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now),
            watchlist: [makeMovieWatchlistItem()],
            history: [makeMovieHistoryItem(historyID: 7001, watchedAt: .now)]
        )
        let engine = SyncEngine(
            persistence: persistence,
            trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a")
        )
        let progress = SyncProgressCollector()

        try await engine.ensureInitialBaseline { update in
            await progress.record(update)
        }

        let snapshot = await remote.snapshot()
        #expect(snapshot.getLastActivitiesCalls == 1)
        #expect(snapshot.getWatchlistCalls == 1)
        #expect(snapshot.getHistoryCalls == 1)
        #expect(snapshot.addWatchlistCalls == 0)
        #expect(snapshot.removeWatchlistCalls == 0)
        #expect(snapshot.addHistoryCalls == 0)
        #expect(snapshot.removeHistoryCalls == 0)

        let states = try fetchAll(SyncStateRecord.self, from: persistence)
        let watchlistRows = try fetchAll(WatchlistRecord.self, from: persistence)
        let events = try fetchAll(WatchedEventRecord.self, from: persistence)

        #expect(states.first?.initialBaselineComplete == true)
        #expect(watchlistRows.count == 1)
        #expect(events.count == 1)

        let progressUpdates = await progress.values
        #expect(progressUpdates.contains(.downloadingWatchlist(1)))
        #expect(progressUpdates.contains(.downloadingHistory(1)))
        #expect(progressUpdates.contains(.downloadingShowProgress))
        #expect(progressUpdates.contains(.saving(watchlistItems: 1, historyItems: 1)))

        let diagnostics = await engine.diagnostics()
        #expect(diagnostics.importedMovieCount == 1)
        #expect(diagnostics.importedShowCount == 0)
        #expect(diagnostics.importedHistoryCount == 1)
    }

    @Test
    func remoteMissingWatchlistDoesNotDeleteLocalState() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()
        let mediaID = MediaID(kind: .movie, id: 11, traktID: 111)

        context.insert(WatchlistRecord(mediaID: mediaID, isInWatchlist: true, dirty: false))
        try context.save()

        let remote = FakeTraktSyncRemote(
            token: makeToken(),
            lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now),
            watchlist: [],
            history: []
        )
        let engine = SyncEngine(
            persistence: persistence,
            trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a")
        )

        try await engine.ensureInitialBaseline()

        let rows = try fetchAll(WatchlistRecord.self, from: persistence)
        #expect(rows.count == 1)
        #expect(rows[0].isInWatchlist == true)
        #expect(rows[0].dirty == false)
    }

    @Test
    func dirtyWatchlistRowsArePreservedDuringPull() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()
        let mediaID = MediaID(kind: .show, id: 22, traktID: 222)

        context.insert(WatchlistRecord(mediaID: mediaID, isInWatchlist: true, dirty: true))
        try context.save()

        let remote = FakeTraktSyncRemote(
            token: makeToken(),
            lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now),
            watchlist: [],
            history: []
        )
        let engine = SyncEngine(
            persistence: persistence,
            trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a")
        )

        try await engine.ensureInitialBaseline()

        let rows = try fetchAll(WatchlistRecord.self, from: persistence)
        #expect(rows.count == 1)
        #expect(rows[0].isInWatchlist == true)
        #expect(rows[0].dirty == true)
    }

    @Test
    func watchedHistoryMergeDeduplicatesLocalPendingEvents() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()
        let watchedAt = Date()

        context.insert(
            WatchedEventRecord(
                kind: .movie,
                tmdbID: 11,
                traktID: nil,
                watchedAt: watchedAt,
                dirty: true
            )
        )
        try context.save()

        let remote = FakeTraktSyncRemote(
            token: makeToken(),
            lastActivities: makeLastActivities(watchlistAt: .now, historyAt: watchedAt),
            watchlist: [],
            history: [makeMovieHistoryItem(historyID: 7002, watchedAt: watchedAt)]
        )
        let engine = SyncEngine(
            persistence: persistence,
            trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a")
        )

        try await engine.ensureInitialBaseline()

        let events = try fetchAll(WatchedEventRecord.self, from: persistence)
        #expect(events.count == 1)
        #expect(events[0].traktHistoryID == 7002)
        #expect(events[0].dirty == false)
        #expect(events[0].traktID == 111)
    }

    @Test
    func dirtyTombstonedHistoryIsPreservedDuringPull() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()
        let watchedAt = Date()

        context.insert(
            WatchedEventRecord(
                kind: .movie,
                tmdbID: 11,
                traktID: 111,
                watchedAt: watchedAt,
                traktHistoryID: 7002,
                dirty: true,
                tombstoned: true
            )
        )
        try context.save()

        let remote = FakeTraktSyncRemote(
            token: makeToken(),
            lastActivities: makeLastActivities(watchlistAt: .now, historyAt: watchedAt),
            watchlist: [],
            history: [makeMovieHistoryItem(historyID: 7002, watchedAt: watchedAt)]
        )
        let engine = SyncEngine(
            persistence: persistence,
            trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a")
        )

        try await engine.ensureInitialBaseline()

        let events = try fetchAll(WatchedEventRecord.self, from: persistence)
        #expect(events.count == 1)
        #expect(events[0].tombstoned == true)
        #expect(events[0].dirty == true)
        #expect(events[0].traktHistoryID == 7002)
    }

    @Test
    func explicitUnwatchOnlyTargetsSelectedEvent() async throws {
        let persistence = makePersistence()
        let repository = makeLibraryRepository(persistence: persistence)
        let context = persistence.makeContext()

        let first = WatchedEventRecord(
            kind: .movie,
            tmdbID: 11,
            traktID: 111,
            watchedAt: Date().addingTimeInterval(-3600),
            traktHistoryID: 9001
        )
        let second = WatchedEventRecord(
            kind: .movie,
            tmdbID: 11,
            traktID: 111,
            watchedAt: Date(),
            traktHistoryID: 9002
        )

        context.insert(first)
        context.insert(second)
        try context.save()

        try await repository.removeWatchEvent(eventID: first.recordID)

        let events = try fetchAll(WatchedEventRecord.self, from: persistence)
        let operations = try fetchAll(SyncOperationRecord.self, from: persistence)
        let payload = try SyncPayloadCodec.decoder.decode(SyncOperationPayload.self, from: try #require(operations.first).payload)

        #expect(events.count == 2)
        #expect(events.first(where: { $0.recordID == first.recordID })?.tombstoned == true)
        #expect(events.first(where: { $0.recordID == second.recordID })?.tombstoned == false)
        #expect(operations.count == 1)
        #expect(payload.historyID == 9001)
    }

    @Test
    func showProgressIsDerivedFromEpisodeEvents() async throws {
        let persistence = makePersistence()
        let repository = makeLibraryRepository(persistence: persistence)
        let context = persistence.makeContext()

        context.insert(
            MediaRecord(
                kind: .show,
                tmdbID: 202,
                traktID: 2002,
                title: "Progress Show",
                overview: "A show for progress testing.",
                posterPath: "/show.jpg",
                totalEpisodes: 2,
                seasonsData: try JSONEncoder().encode([
                    StoredShowSeason(id: 1, traktID: 1, seasonNumber: 1, name: "Season 1", episodeCount: 2, posterPath: "/season.jpg")
                ])
            )
        )
        context.insert(
            EpisodeRecord(
                showTMDbID: 202,
                showTraktID: 2002,
                tmdbID: 301,
                traktID: 3001,
                seasonNumber: 1,
                episodeNumber: 1,
                name: "Episode 1",
                airDate: Calendar.current.date(byAdding: .day, value: -5, to: .now)
            )
        )
        context.insert(
            EpisodeRecord(
                showTMDbID: 202,
                showTraktID: 2002,
                tmdbID: 302,
                traktID: 3002,
                seasonNumber: 1,
                episodeNumber: 2,
                name: "Episode 2",
                airDate: Calendar.current.date(byAdding: .day, value: -1, to: .now)
            )
        )
        context.insert(
            WatchedEventRecord(
                kind: .episode,
                tmdbID: 301,
                traktID: 3001,
                showTMDbID: 202,
                showTraktID: 2002,
                seasonNumber: 1,
                episodeNumber: 1,
                watchedAt: Date().addingTimeInterval(-7200)
            )
        )
        try context.save()

        let progress = try await repository.showProgress(for: MediaID(kind: .show, id: 202, traktID: 2002))

        #expect(progress.watchedCount == 1)
        #expect(progress.remainingReleased == 1)
        #expect(progress.nextEpisode?.season == 1)
        #expect(progress.nextEpisode?.episode == 2)
        #expect(progress.nextEpisode?.tmdbID == 302)
    }

    @Test
    func importedShowLibraryRendersBeforeRemoteMetadataEnrichment() async throws {
        let persistence = makePersistence()
        let repository = makeLibraryRepository(persistence: persistence)
        let context = persistence.makeContext()
        let showID = MediaID(kind: .show, id: 515, traktID: 5_150)

        context.insert(
            MediaRecord(
                kind: .show,
                tmdbID: showID.tmdbID,
                traktID: showID.traktID,
                title: "Imported Show"
            )
        )
        context.insert(WatchlistRecord(mediaID: showID, isInWatchlist: true))
        try context.save()

        let items = try await repository.showLibraryItems()

        #expect(items.count == 1)
        #expect(items.first?.title == "Imported Show")
        #expect(items.first?.posterPath == nil)
        #expect(items.first?.progress.watchedCount == 0)
        #expect(items.first?.progress.nextEpisode == nil)
        #expect(items.first?.needsProgressEnrichment == true)
    }

    @Test
    func showProgressIgnoresSeasonZeroForNextUpAndRemainingCount() async throws {
        let persistence = makePersistence()
        let repository = makeLibraryRepository(persistence: persistence)
        let context = persistence.makeContext()

        context.insert(
            MediaRecord(
                kind: .show,
                tmdbID: 400,
                traktID: 4000,
                title: "Specials Show",
                overview: "A show with specials.",
                posterPath: "/show.jpg",
                totalEpisodes: 2,
                seasonsData: try JSONEncoder().encode([
                    StoredShowSeason(id: 9, traktID: 9000, seasonNumber: 0, name: "Specials", episodeCount: 1, posterPath: "/specials.jpg"),
                    StoredShowSeason(id: 10, traktID: 1000, seasonNumber: 1, name: "Season 1", episodeCount: 2, posterPath: "/season1.jpg")
                ])
            )
        )
        context.insert(
            EpisodeRecord(
                showTMDbID: 400,
                showTraktID: 4000,
                tmdbID: 401,
                traktID: 4001,
                seasonNumber: 0,
                episodeNumber: 1,
                name: "Bonus Episode",
                airDate: Calendar.current.date(byAdding: .day, value: -10, to: .now)
            )
        )
        context.insert(
            EpisodeRecord(
                showTMDbID: 400,
                showTraktID: 4000,
                tmdbID: 402,
                traktID: 4002,
                seasonNumber: 1,
                episodeNumber: 1,
                name: "Pilot",
                airDate: Calendar.current.date(byAdding: .day, value: -5, to: .now)
            )
        )
        context.insert(
            EpisodeRecord(
                showTMDbID: 400,
                showTraktID: 4000,
                tmdbID: 403,
                traktID: 4003,
                seasonNumber: 1,
                episodeNumber: 2,
                name: "Second Episode",
                airDate: Calendar.current.date(byAdding: .day, value: -1, to: .now)
            )
        )
        context.insert(
            WatchedEventRecord(
                kind: .episode,
                tmdbID: 401,
                traktID: 4001,
                showTMDbID: 400,
                showTraktID: 4000,
                seasonNumber: 0,
                episodeNumber: 1,
                watchedAt: Date().addingTimeInterval(-86_400)
            )
        )
        try context.save()

        let progress = try await repository.showProgress(for: MediaID(kind: .show, id: 400, traktID: 4000))

        #expect(progress.remainingReleased == 2)
        #expect(progress.nextEpisode?.season == 1)
        #expect(progress.nextEpisode?.episode == 1)
        #expect(progress.watchedEpisodeKeys.contains("ep:400:S0:E1") == true)
    }

    @Test
    func outboxClaimPreventsDoublePushAcrossEngines() async throws {
        TraktLinkStore.activeAccountKey = "default"
        defer { TraktLinkStore.clear() }
        let persistence = makePersistence()
        let context = persistence.makeContext()
        let mediaID = MediaID(kind: .movie, id: 11, traktID: 111)

        context.insert(WatchlistRecord(mediaID: mediaID, isInWatchlist: true, dirty: true))
        context.insert(SyncStateRecord(accountKey: "default", initialBaselineComplete: true))
        context.insert(
            SyncOperationRecord(
                kind: .addWatchlist,
                payload: try SyncPayloadCodec.encoder.encode(
                    SyncOperationPayload(mediaKind: .movie, tmdbID: 11, traktID: 111)
                ),
                dedupeKey: "watchlist:movie:11",
                accountKey: "default"
            )
        )
        try context.save()

        let remote = FakeTraktSyncRemote(
            token: makeToken(),
            lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now),
            watchlist: [],
            history: [],
            addWatchlistDelayNanos: 150_000_000
        )
        let engineA = SyncEngine(
            persistence: persistence,
            trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a")
        )
        let engineB = SyncEngine(
            persistence: persistence,
            trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-b")
        )

        async let runA = engineA.run(reason: .background)
        async let runB = engineB.run(reason: .background)
        _ = await (runA, runB)

        let snapshot = await remote.snapshot()
        let operations = try fetchAll(SyncOperationRecord.self, from: persistence)
        let watchlistRows = try fetchAll(WatchlistRecord.self, from: persistence)

        #expect(snapshot.addWatchlistCalls == 1)
        #expect(operations.first?.status == .succeeded)
        #expect(watchlistRows.first?.dirty == false)
    }

    @Test
    func foregroundRefreshRunsWhenOutboxHasPendingOperations() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()

        context.insert(
            SyncOperationRecord(
                kind: .addWatchlist,
                payload: try SyncPayloadCodec.encoder.encode(
                    SyncOperationPayload(mediaKind: .movie, tmdbID: 11, traktID: 111)
                ),
                dedupeKey: "watchlist:movie:11"
            )
        )
        try context.save()

        let engine = SyncEngine(
            persistence: persistence,
            trakt: FakeTraktSyncRemote(
                token: makeToken(),
                lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now),
                watchlist: [],
                history: []
            ),
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a")
        )

        let shouldRefresh = await engine.shouldRefreshOnForeground(maxStaleness: 60 * 60)
        #expect(shouldRefresh == true)
    }

    @Test
    func foregroundRefreshSkipsWhenRecentAndIdle() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()

        context.insert(
            SyncStateRecord(
                accountKey: "default",
                initialBaselineComplete: true,
                lastSuccessfulPullAt: Date(),
                lastSuccessfulPushAt: Date()
            )
        )
        try context.save()

        let engine = SyncEngine(
            persistence: persistence,
            trakt: FakeTraktSyncRemote(
                token: makeToken(),
                lastActivities: makeLastActivities(
                    watchlistAt: Date().addingTimeInterval(-60),
                    historyAt: Date().addingTimeInterval(-60)
                ),
                watchlist: [],
                history: []
            ),
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a")
        )

        let shouldRefresh = await engine.shouldRefreshOnForeground(maxStaleness: 60 * 60)
        #expect(shouldRefresh == false)
    }

    @Test
    func incrementalSyncSkipsUnchangedWatchlistAndHistoryPulls() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()
        let previousActivity = Date()

        context.insert(
            SyncStateRecord(
                accountKey: "default",
                initialBaselineComplete: true,
                lastSuccessfulPullAt: previousActivity,
                lastSuccessfulPushAt: previousActivity,
                lastSeenRemoteActivityAt: previousActivity
            )
        )
        try context.save()

        let remote = FakeTraktSyncRemote(
            token: makeToken(),
            lastActivities: makeLastActivities(
                watchlistAt: previousActivity.addingTimeInterval(-60),
                historyAt: previousActivity.addingTimeInterval(-60)
            ),
            watchlist: [makeMovieWatchlistItem()],
            history: [makeMovieHistoryItem(historyID: 999, watchedAt: previousActivity)]
        )
        let engine = SyncEngine(
            persistence: persistence,
            trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a")
        )

        let succeeded = await engine.run(reason: .foreground)
        let snapshot = await remote.snapshot()

        #expect(succeeded == true)
        #expect(snapshot.getLastActivitiesCalls == 1)
        #expect(snapshot.getWatchlistCalls == 0)
        #expect(snapshot.getHistoryCalls == 0)
        #expect(snapshot.getActiveShowProgressCalls == 1)
    }

    @Test
    func watchlistRemovalIsReconciledWhenRemoteActivityAdvances() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()
        let mediaID = MediaID(kind: .movie, id: 11, traktID: 111)
        let oldActivity = Date().addingTimeInterval(-3600)

        context.insert(
            WatchlistRecord(
                mediaID: mediaID,
                isInWatchlist: true,
                listedAt: oldActivity,
                localUpdatedAt: oldActivity,
                remoteUpdatedAt: oldActivity,
                dirty: false
            )
        )
        context.insert(
            SyncStateRecord(
                accountKey: "default",
                initialBaselineComplete: true,
                lastSuccessfulPullAt: oldActivity,
                lastSuccessfulPushAt: oldActivity,
                lastSeenRemoteActivityAt: oldActivity
            )
        )
        try context.save()

        let remote = FakeTraktSyncRemote(
            token: makeToken(),
            lastActivities: makeLastActivities(watchlistAt: .now, historyAt: oldActivity),
            watchlist: [],
            history: []
        )
        let engine = SyncEngine(
            persistence: persistence,
            trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a")
        )

        let succeeded = await engine.run(reason: .foreground)
        let rows = try fetchAll(WatchlistRecord.self, from: persistence)

        #expect(succeeded == true)
        #expect(rows.count == 1)
        #expect(rows[0].isInWatchlist == false)
        #expect(rows[0].dirty == false)
    }

    @Test
    func activeTraktProgressSeedsDurableFollowing() async throws {
        let persistence = makePersistence()
        let remote = FakeTraktSyncRemote(
            token: makeToken(),
            lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now),
            watchlist: [],
            history: [makeEpisodeHistoryItem(historyID: 8001, watchedAt: .now)],
            activeShowProgress: [makeActiveShowProgress()]
        )
        let engine = SyncEngine(
            persistence: persistence,
            trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a")
        )

        try await engine.ensureInitialBaseline()

        let rows = try fetchAll(WatchlistRecord.self, from: persistence)
        #expect(rows.count == 1)
        #expect(rows[0].mediaID.kind == .show)
        #expect(rows[0].tmdbID == 22)
        #expect(rows[0].isInWatchlist == true)
        #expect(rows[0].dirty == false)
        #expect(try fetchAll(SyncOperationRecord.self, from: persistence).isEmpty)
    }

    @Test
    func activeProgressDoesNotUndoExplicitUnfollow() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()
        context.insert(
            WatchlistRecord(
                mediaID: MediaID(kind: .show, id: 22, traktID: 222),
                isInWatchlist: false,
                dirty: false
            )
        )
        try context.save()

        let engine = SyncEngine(
            persistence: persistence,
            trakt: FakeTraktSyncRemote(
                token: makeToken(),
                lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now),
                watchlist: [],
                history: [makeEpisodeHistoryItem(historyID: 8001, watchedAt: .now)],
                activeShowProgress: [makeActiveShowProgress()]
            ),
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a")
        )

        try await engine.ensureInitialBaseline()

        let rows = try fetchAll(WatchlistRecord.self, from: persistence)
        #expect(rows.count == 1)
        #expect(rows[0].isInWatchlist == false)
    }

    @Test
    func watchedItemStaysFollowedAfterTraktAutoRemovesItFromWatchlist() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()
        let oldActivity = Date().addingTimeInterval(-3600)
        context.insert(
            WatchlistRecord(
                mediaID: MediaID(kind: .movie, id: 11, traktID: 111),
                isInWatchlist: true,
                localUpdatedAt: oldActivity,
                remoteUpdatedAt: oldActivity,
                dirty: false
            )
        )
        context.insert(
            SyncStateRecord(
                accountKey: "default",
                initialBaselineComplete: true,
                lastSuccessfulPullAt: oldActivity,
                lastSuccessfulPushAt: oldActivity,
                lastSeenRemoteActivityAt: oldActivity
            )
        )
        try context.save()

        let engine = SyncEngine(
            persistence: persistence,
            trakt: FakeTraktSyncRemote(
                token: makeToken(),
                lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now),
                watchlist: [],
                history: [makeMovieHistoryItem(historyID: 7001, watchedAt: .now)]
            ),
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a")
        )

        #expect(await engine.run(reason: .foreground) == true)
        let rows = try fetchAll(WatchlistRecord.self, from: persistence)
        #expect(rows.count == 1)
        #expect(rows[0].isInWatchlist == true)
    }

    @Test
    func retryDeadletterOperationsRequeuesFailedWork() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()

        context.insert(
            SyncOperationRecord(
                kind: .addWatchlist,
                payload: try SyncPayloadCodec.encoder.encode(
                    SyncOperationPayload(mediaKind: .movie, tmdbID: 11, traktID: 111)
                ),
                dedupeKey: "watchlist:movie:11",
                status: .deadletter
            )
        )
        try context.save()

        let engine = SyncEngine(
            persistence: persistence,
            trakt: FakeTraktSyncRemote(
                token: makeToken(),
                lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now),
                watchlist: [],
                history: []
            ),
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a")
        )

        let retried = try await engine.retryDeadletterOperations()
        let operations = try fetchAll(SyncOperationRecord.self, from: persistence)

        #expect(retried == 1)
        #expect(operations.first?.status == .pending)
        #expect(operations.first?.attemptCount == 0)
    }

    @Test
    func repairIntegrityDeduplicatesLogicalRecords() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()
        let watchedAt = Date()

        context.insert(MediaRecord(kind: .movie, tmdbID: 11, traktID: 111, title: "Movie"))
        context.insert(MediaRecord(kind: .movie, tmdbID: 11, traktID: 111, title: ""))
        context.insert(WatchlistRecord(mediaID: MediaID(kind: .movie, id: 11, traktID: 111), isInWatchlist: true))
        context.insert(WatchlistRecord(mediaID: MediaID(kind: .movie, id: 11, traktID: 111), isInWatchlist: true))
        context.insert(WatchedEventRecord(kind: .movie, tmdbID: 11, traktID: nil, watchedAt: watchedAt))
        context.insert(WatchedEventRecord(kind: .movie, tmdbID: 11, traktID: 111, watchedAt: watchedAt))
        try context.save()

        let engine = SyncEngine(
            persistence: persistence,
            trakt: FakeTraktSyncRemote(
                token: makeToken(),
                lastActivities: makeLastActivities(watchlistAt: .now, historyAt: watchedAt),
                watchlist: [],
                history: []
            ),
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a")
        )

        let summary = try await engine.repairIntegrity()

        #expect(summary.mediaMerged == 1)
        #expect(summary.watchlistMerged == 1)
        #expect(summary.watchedEventsMerged == 1)
        #expect(try fetchAll(MediaRecord.self, from: persistence).count == 1)
        #expect(try fetchAll(WatchlistRecord.self, from: persistence).count == 1)
        #expect(try fetchAll(WatchedEventRecord.self, from: persistence).count == 1)
    }

    @Test
    func swiftDataRoundTripPersistsNewFoundationRecords() throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()

        context.insert(MediaRecord(kind: .movie, tmdbID: 1, traktID: 10, title: "Round Trip"))
        context.insert(
            EpisodeRecord(
                showTMDbID: 2,
                showTraktID: 20,
                tmdbID: 3,
                traktID: 30,
                seasonNumber: 1,
                episodeNumber: 1,
                name: "Pilot"
            )
        )
        context.insert(WatchlistRecord(mediaID: MediaID(kind: .movie, id: 1, traktID: 10), isInWatchlist: true))
        context.insert(WatchedEventRecord(kind: .movie, tmdbID: 1, traktID: 10, watchedAt: .now))
        context.insert(
            SyncOperationRecord(
                kind: .addWatchlist,
                payload: try SyncPayloadCodec.encoder.encode(SyncOperationPayload(mediaKind: .movie, tmdbID: 1, traktID: 10))
            )
        )
        context.insert(SyncStateRecord(accountKey: "default"))
        try context.save()

        #expect(try fetchAll(MediaRecord.self, from: persistence).count == 1)
        #expect(try fetchAll(EpisodeRecord.self, from: persistence).count == 1)
        #expect(try fetchAll(WatchlistRecord.self, from: persistence).count == 1)
        #expect(try fetchAll(WatchedEventRecord.self, from: persistence).count == 1)
        #expect(try fetchAll(SyncOperationRecord.self, from: persistence).count == 1)
        #expect(try fetchAll(SyncStateRecord.self, from: persistence).count == 1)
    }

    @Test
    func cloudKitCompatibleSchemaLoads() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("iWatch-cloudkit-\(UUID().uuidString).store")
        defer { removeStoreArtifacts(at: storeURL) }

        let persistence = Persistence(
            inMemory: false,
            storeURL: storeURL,
            cloudKitDatabase: .private("iCloud.com.tyler.iWatch")
        )
        let context = persistence.makeContext()

        context.insert(MediaRecord(kind: .movie, tmdbID: 99, traktID: 199, title: "CloudKit Ready"))
        try context.save()

        #expect(try fetchAll(MediaRecord.self, from: persistence).count == 1)
    }

    @Test
    func eraseAllAppDataRemovesAllPersistedRecords() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()

        context.insert(MediaRecord(kind: .movie, tmdbID: 1, traktID: 10, title: "Reset Me"))
        context.insert(
            EpisodeRecord(
                showTMDbID: 2,
                showTraktID: 20,
                tmdbID: 3,
                traktID: 30,
                seasonNumber: 1,
                episodeNumber: 1,
                name: "Pilot"
            )
        )
        context.insert(WatchlistRecord(mediaID: MediaID(kind: .movie, id: 1, traktID: 10), isInWatchlist: true))
        context.insert(WatchedEventRecord(kind: .movie, tmdbID: 1, traktID: 10, watchedAt: .now))
        context.insert(
            SyncOperationRecord(
                kind: .addWatchlist,
                payload: try SyncPayloadCodec.encoder.encode(SyncOperationPayload(mediaKind: .movie, tmdbID: 1, traktID: 10))
            )
        )
        context.insert(SyncStateRecord(accountKey: "default"))
        try context.save()

        let engine = SyncEngine(
            persistence: persistence,
            trakt: FakeTraktSyncRemote(
                token: makeToken(),
                lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now),
                watchlist: [],
                history: []
            ),
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a")
        )

        try await engine.eraseAllAppData()

        #expect(try fetchAll(MediaRecord.self, from: persistence).isEmpty)
        #expect(try fetchAll(EpisodeRecord.self, from: persistence).isEmpty)
        #expect(try fetchAll(WatchlistRecord.self, from: persistence).isEmpty)
        #expect(try fetchAll(WatchedEventRecord.self, from: persistence).isEmpty)
        #expect(try fetchAll(SyncOperationRecord.self, from: persistence).isEmpty)
        #expect(try fetchAll(SyncStateRecord.self, from: persistence).isEmpty)
        #expect(try fetchAll(LibraryGenerationRecord.self, from: persistence).count == 1)
    }

    @Test
    func resetGenerationRejectsRecordsReturningFromAnOfflineDevice() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()
        let mediaID = MediaID(kind: .movie, id: 42, traktID: 420)
        context.insert(
            WatchlistRecord(
                mediaID: mediaID,
                isInWatchlist: true,
                generationID: LibraryGenerationPolicy.legacyGenerationID
            )
        )
        try context.save()

        let engine = SyncEngine(
            persistence: persistence,
            trakt: FakeTraktSyncRemote(
                token: makeToken(),
                lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now),
                watchlist: [],
                history: []
            ),
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a")
        )
        try await engine.eraseAllAppData()

        let staleContext = persistence.makeContext()
        staleContext.insert(
            WatchlistRecord(
                mediaID: mediaID,
                isInWatchlist: true,
                generationID: LibraryGenerationPolicy.legacyGenerationID
            )
        )
        try staleContext.save()

        let repository = makeLibraryRepository(persistence: persistence)
        #expect(await repository.isInWatchlist(mediaID) == false)

        let currentContext = persistence.makeContext()
        let currentGeneration = LibraryGenerationPolicy.currentGeneration(in: currentContext)
        currentContext.insert(
            WatchlistRecord(
                mediaID: mediaID,
                isInWatchlist: true,
                generationID: currentGeneration
            )
        )
        try currentContext.save()

        #expect(await repository.isInWatchlist(mediaID) == true)
    }

    @Test @MainActor
    func libraryMutationsAreBlockedWhileResetIsInProgress() async throws {
        let persistence = makePersistence()
        let gate = AppDataResetGate()
        let repository = makeLibraryRepository(persistence: persistence, resetGate: gate)
        let mediaID = MediaID(kind: .movie, id: 88, traktID: 880)

        await gate.beginReset()
        do {
            try await repository.setWatchlist(true, for: mediaID)
            Issue.record("Expected the reset gate to reject the library mutation")
        } catch {
            // Expected: user mutations are held until reset finishes.
        }
        await gate.endReset()

        #expect(try fetchAll(WatchlistRecord.self, from: persistence).isEmpty)
        try await repository.setWatchlist(true, for: mediaID)
        #expect(try fetchAll(WatchlistRecord.self, from: persistence).count == 1)
    }


    @Test
    func viewsDoNotDependOnRemoteClientsOrPersistenceRecordsDirectly() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewsURL = root.appendingPathComponent("iWatch/Views")
        let files = try FileManager.default.subpathsOfDirectory(atPath: viewsURL.path)
            .filter { $0.hasSuffix(".swift") && !$0.contains("ShowsView-Backup") }

        let disallowedSnippets = [
            "TMDbService",
            "TraktService",
            "Persistence(",
            "ModelContext(",
            "FetchDescriptor<",
            "MediaRecord",
            "EpisodeRecord",
            "WatchlistRecord",
            "WatchedEventRecord",
            "SyncOperationRecord",
            "SyncStateRecord",
        ]

        for file in files {
            let contents = try String(contentsOf: viewsURL.appendingPathComponent(file), encoding: .utf8)
            for snippet in disallowedSnippets {
                #expect(
                    contents.contains(snippet) == false,
                    Comment("Found disallowed dependency '\(snippet)' in \(file)")
                )
            }
        }
    }
}

private func makePersistence() -> Persistence {
    Persistence(inMemory: true, cloudKitDatabase: ModelConfiguration.CloudKitDatabase.none)
}

@MainActor
private func makeLibraryRepository(
    persistence: Persistence,
    resetGate: AppDataResetGate = AppDataResetGate()
) -> LibraryRepository {
    let apiClient = APIClient(session: .shared)
    let tmdb = TMDbService(apiClient: apiClient, apiKey: "test-key")
    return LibraryRepository(persistence: persistence, tmdb: tmdb, resetGate: resetGate)
}

private func fetchAll<T: PersistentModel>(_ type: T.Type, from persistence: Persistence) throws -> [T] {
    try persistence.makeContext().fetch(FetchDescriptor<T>())
}

private func removeStoreArtifacts(at url: URL) {
    let fm = FileManager.default
    try? fm.removeItem(at: url)
    try? fm.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
    try? fm.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
}

private func makeToken() -> TokenResponse {
    TokenResponse(
        accessToken: "access",
        tokenType: "bearer",
        expiresIn: 3600,
        refreshToken: "refresh",
        scope: "public",
        createdAt: Int(Date().timeIntervalSince1970)
    )
}

private func makeMovieWatchlistItem() -> TraktWatchlistItemDTO {
    TraktWatchlistItemDTO(
        type: .movie,
        listedAt: .now,
        movie: TraktMovieDTO(
            title: "Tracked Movie",
            year: 2024,
            ids: TraktIDs(trakt: 111, slug: nil, tmdb: 11, imdb: nil)
        ),
        show: nil,
        season: nil,
        episode: nil
    )
}

private func makeMovieHistoryItem(historyID: Int, watchedAt: Date) -> TraktHistoryItemDTO {
    TraktHistoryItemDTO(
        id: historyID,
        watchedAt: watchedAt,
        action: "scrobble",
        type: .movie,
        movie: TraktMovieDTO(
            title: "Tracked Movie",
            year: 2024,
            ids: TraktIDs(trakt: 111, slug: nil, tmdb: 11, imdb: nil)
        ),
        show: nil,
        season: nil,
        episode: nil
    )
}

private func makeEpisodeHistoryItem(historyID: Int, watchedAt: Date) -> TraktHistoryItemDTO {
    TraktHistoryItemDTO(
        id: historyID,
        watchedAt: watchedAt,
        action: "scrobble",
        type: .episode,
        movie: nil,
        show: TraktShowDTO(
            title: "Tracked Show",
            year: 2024,
            ids: TraktIDs(trakt: 222, slug: nil, tmdb: 22, imdb: nil)
        ),
        season: nil,
        episode: TraktEpisodeDTO(
            season: 1,
            number: 1,
            title: "Pilot",
            ids: TraktIDs(trakt: 333, slug: nil, tmdb: 33, imdb: nil)
        )
    )
}

private func makeActiveShowProgress() -> TraktShowProgressDTO {
    TraktShowProgressDTO(
        show: TraktShowDTO(
            title: "Tracked Show",
            year: 2024,
            ids: TraktIDs(trakt: 222, slug: nil, tmdb: 22, imdb: nil)
        ),
        progress: TraktShowProgressSummaryDTO(
            aired: 10,
            completed: 1,
            lastWatchedAt: .now
        )
    )
}

private func makeLastActivities(watchlistAt: Date?, historyAt: Date?) -> TraktLastActivitiesDTO {
    TraktLastActivitiesDTO(
        all: [watchlistAt, historyAt].compactMap { $0 }.max(),
        movies: TraktActivityGroupDTO(watchedAt: historyAt, watchlistedAt: watchlistAt),
        episodes: TraktActivityGroupDTO(watchedAt: historyAt, watchlistedAt: nil),
        shows: TraktActivityGroupDTO(watchedAt: nil, watchlistedAt: watchlistAt),
        watchlist: TraktActivityTimestampDTO(updatedAt: watchlistAt)
    )
}

private actor FixedDeviceIdentityStore: DeviceIdentityStore {
    let id: String

    init(id: String) {
        self.id = id
    }

    func currentDeviceID() async -> String {
        id
    }
}

private actor SyncProgressCollector {
    private(set) var values: [SyncProgress] = []

    func record(_ value: SyncProgress) {
        values.append(value)
    }
}

private actor FakeTraktSyncRemote: TraktSyncing {
    struct Snapshot {
        let getLastActivitiesCalls: Int
        let getWatchlistCalls: Int
        let getHistoryCalls: Int
        let getActiveShowProgressCalls: Int
        let addWatchlistCalls: Int
        let removeWatchlistCalls: Int
        let addHistoryCalls: Int
        let removeHistoryCalls: Int
    }

    private let token: TokenResponse?
    private let lastActivities: TraktLastActivitiesDTO
    private let watchlist: [TraktWatchlistItemDTO]
    private let history: [TraktHistoryItemDTO]
    private let activeShowProgress: [TraktShowProgressDTO]
    private let addWatchlistDelayNanos: UInt64

    private var getLastActivitiesCalls = 0
    private var getWatchlistCalls = 0
    private var getHistoryCalls = 0
    private var getActiveShowProgressCalls = 0
    private var addWatchlistCalls = 0
    private var removeWatchlistCalls = 0
    private var addHistoryCalls = 0
    private var removeHistoryCalls = 0

    init(token: TokenResponse?,
         lastActivities: TraktLastActivitiesDTO,
         watchlist: [TraktWatchlistItemDTO],
         history: [TraktHistoryItemDTO],
         activeShowProgress: [TraktShowProgressDTO] = [],
         addWatchlistDelayNanos: UInt64 = 0) {
        self.token = token
        self.lastActivities = lastActivities
        self.watchlist = watchlist
        self.history = history
        self.activeShowProgress = activeShowProgress
        self.addWatchlistDelayNanos = addWatchlistDelayNanos
    }

    func currentToken() async -> TokenResponse? {
        token
    }

    func getLastActivities() async throws -> TraktLastActivitiesDTO {
        getLastActivitiesCalls += 1
        return lastActivities
    }

    func getWatchlist() async throws -> [TraktWatchlistItemDTO] {
        getWatchlistCalls += 1
        return watchlist
    }

    func getHistory(startAt: Date?) async throws -> [TraktHistoryItemDTO] {
        getHistoryCalls += 1
        return history
    }

    func getActiveShowProgress() async throws -> [TraktShowProgressDTO] {
        getActiveShowProgressCalls += 1
        return activeShowProgress
    }

    func addToWatchlist(_ items: [MediaID]) async throws {
        addWatchlistCalls += 1
        if addWatchlistDelayNanos > 0 {
            try await Task.sleep(nanoseconds: addWatchlistDelayNanos)
        }
        #expect(items.isEmpty == false)
    }

    func removeFromWatchlist(_ items: [MediaID]) async throws {
        removeWatchlistCalls += 1
        #expect(items.isEmpty == false)
    }

    func addToHistory(_ payloads: [SyncOperationPayload]) async throws {
        addHistoryCalls += 1
        #expect(payloads.isEmpty == false)
    }

    func removeFromHistory(historyIDs: [Int]) async throws {
        removeHistoryCalls += 1
        #expect(historyIDs.isEmpty == false)
    }

    func snapshot() -> Snapshot {
        Snapshot(
            getLastActivitiesCalls: getLastActivitiesCalls,
            getWatchlistCalls: getWatchlistCalls,
            getHistoryCalls: getHistoryCalls,
            getActiveShowProgressCalls: getActiveShowProgressCalls,
            addWatchlistCalls: addWatchlistCalls,
            removeWatchlistCalls: removeWatchlistCalls,
            addHistoryCalls: addHistoryCalls,
            removeHistoryCalls: removeHistoryCalls
        )
    }
}
