import Foundation
import CloudKit
import SwiftData
import Testing
@testable import iWatch

// MARK: - Foundation and Sync Tests

@MainActor
struct FoundationRewriteTests {
    // MARK: Initial Sync

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
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"),
            accountKeyProvider: { "default" }
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
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"),
            accountKeyProvider: { "default" }
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
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"),
            accountKeyProvider: { "default" }
        )

        try await engine.ensureInitialBaseline()

        let rows = try fetchAll(WatchlistRecord.self, from: persistence)
        #expect(rows.count == 1)
        #expect(rows[0].isInWatchlist == true)
        #expect(rows[0].dirty == true)
    }

    // MARK: History and Library Mutations

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
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"),
            accountKeyProvider: { "default" }
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
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"),
            accountKeyProvider: { "default" }
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
    func markingWatchlistedMovieWatchedMovesItToHistory() async throws {
        let persistence = makePersistence()
        let repository = makeLibraryRepository(persistence: persistence)
        let context = persistence.makeContext()
        let movieID = MediaID(kind: .movie, id: 11, traktID: 111)
        context.insert(WatchlistRecord(mediaID: movieID, isInWatchlist: true))
        try context.save()

        try await repository.addWatchEvent(for: movieID, watchedAt: .now)

        let watchlist = try #require(fetchAll(WatchlistRecord.self, from: persistence).first)
        let events = try fetchAll(WatchedEventRecord.self, from: persistence)
        let operations = try fetchAll(SyncOperationRecord.self, from: persistence)
        #expect(watchlist.isInWatchlist == false)
        #expect(events.count == 1)
        #expect(Set(operations.map(\.kind)) == [.addHistory, .removeWatchlist])
    }

    @Test
    func markingFirstEpisodeWatchedMovesParentShowOutOfWatchlistAndResumesIt() async throws {
        let persistence = makePersistence()
        let repository = makeLibraryRepository(persistence: persistence)
        let context = persistence.makeContext()
        let showID = MediaID(kind: .show, id: 22, traktID: 222)
        context.insert(WatchlistRecord(mediaID: showID, isInWatchlist: true))
        context.insert(ShowDispositionRecord(showID: showID, disposition: .stopped))
        context.insert(EpisodeRecord(
            showTMDbID: 22,
            showTraktID: 222,
            tmdbID: 33,
            traktID: 333,
            seasonNumber: 1,
            episodeNumber: 1,
            name: "Pilot",
            airDate: .now
        ))
        try context.save()

        try await repository.addWatchEvent(
            for: MediaID(kind: .episode, id: 33, traktID: 333),
            watchedAt: .now
        )

        #expect(try #require(fetchAll(WatchlistRecord.self, from: persistence).first).isInWatchlist == false)
        #expect(try #require(fetchAll(ShowDispositionRecord.self, from: persistence).first).disposition == .active)
        #expect(try fetchAll(WatchedEventRecord.self, from: persistence).count == 1)
    }

    @Test
    func watchHistoryPreservesRewatchesInReverseChronologicalOrder() async throws {
        let persistence = makePersistence()
        let repository = makeLibraryRepository(persistence: persistence)
        let movieID = MediaID(kind: .movie, id: 11, traktID: 111)
        let earlier = Date().addingTimeInterval(-3_600)
        let later = Date()

        try await repository.addWatchEvent(for: movieID, watchedAt: earlier)
        try await repository.addWatchEvent(for: movieID, watchedAt: later)

        let history = await repository.watchHistory()
        #expect(history.map(\.watchedAt) == [later, earlier])
    }

    @Test
    func additiveDispositionSchemaPreservesExistingWatchlistAndHistory() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("iWatch-lifecycle-migration-\(UUID().uuidString).sqlite")
        defer { removeStoreArtifacts(at: storeURL) }
        let movieID = MediaID(kind: .movie, id: 11, traktID: 111)
        let watchedAt = Date()

        do {
            let legacySchema = Schema([
                MediaRecord.self,
                EpisodeRecord.self,
                WatchlistRecord.self,
                WatchedEventRecord.self,
                SyncOperationRecord.self,
                SyncStateRecord.self,
                LibraryGenerationRecord.self
            ])
            let configuration = ModelConfiguration(
                "iWatch",
                schema: legacySchema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: legacySchema, configurations: [configuration])
            let context = ModelContext(container)
            context.insert(WatchlistRecord(mediaID: movieID, isInWatchlist: true))
            context.insert(WatchedEventRecord(kind: .movie, tmdbID: 11, traktID: 111, watchedAt: watchedAt))
            try context.save()
        }

        let migrated = Persistence(
            storeURL: storeURL,
            cloudKitDatabase: ModelConfiguration.CloudKitDatabase.none
        )
        #expect(try fetchAll(WatchlistRecord.self, from: migrated).count == 1)
        #expect(try fetchAll(WatchedEventRecord.self, from: migrated).first?.watchedAt == watchedAt)
        #expect(try fetchAll(ShowDispositionRecord.self, from: migrated).isEmpty)
    }

    // MARK: Show Progress

    @Test
    func episodeAvailabilityPrefersExactAirtimeOverCalendarDate() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 2_000_000)
        let today = calendar.startOfDay(for: now)

        #expect(
            EpisodeAvailability.isReleased(
                airDate: today,
                airedAt: now.addingTimeInterval(60),
                relativeTo: now,
                calendar: calendar
            ) == false
        )
        #expect(
            EpisodeAvailability.isReleased(
                airDate: today,
                airedAt: now.addingTimeInterval(-60),
                relativeTo: now,
                calendar: calendar
            ) == true
        )
        #expect(
            EpisodeAvailability.isReleased(
                airDate: today,
                airedAt: nil,
                relativeTo: now,
                calendar: calendar
            ) == true
        )
    }

    @Test
    func traktEpisodeDecodesExactFirstAiredTimestamp() throws {
        let data = Data(
            #"{"season":2,"number":3,"title":"Release","first_aired":"2026-08-10T20:00:00.000Z","ids":{"trakt":123,"tmdb":456}}"#
                .utf8
        )

        let episode = try JSONDecoder.trakt.decode(TraktEpisodeDTO.self, from: data)

        #expect(episode.season == 2)
        #expect(episode.number == 3)
        #expect(episode.ids.trakt == 123)
        #expect(episode.firstAired == Date(timeIntervalSince1970: 1_786_392_000))
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
            EpisodeRecord(
                showTMDbID: 202,
                showTraktID: 2002,
                tmdbID: 401,
                traktID: 4001,
                seasonNumber: 2,
                episodeNumber: 1,
                name: "Future Episode",
                airDate: Calendar.current.date(byAdding: .day, value: 7, to: .now)
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
        #expect(progress.nextUpcomingEpisode?.season == 2)
        #expect(progress.nextUpcomingEpisode?.episode == 1)
        #expect(progress.mostRecentWatchedSeason == 1)
    }

    @Test
    func previousEpisodeOfferUsesReleasedRegularViewingOrderAndBatchWritesHistory() async throws {
        let persistence = makePersistence()
        let repository = makeLibraryRepository(persistence: persistence)
        let context = persistence.makeContext()
        let past = Calendar.current.date(byAdding: .day, value: -10, to: .now)!
        let future = Calendar.current.date(byAdding: .day, value: 10, to: .now)!

        context.insert(
            MediaRecord(
                kind: .show,
                tmdbID: 500,
                traktID: 5_000,
                title: "Viewing Order",
                overview: "A show for previous episode testing.",
                totalEpisodes: 5,
                seasonsData: try JSONEncoder().encode([
                    StoredShowSeason(id: 50, traktID: 500, seasonNumber: 0, name: "Specials", episodeCount: 1, posterPath: nil),
                    StoredShowSeason(id: 51, traktID: 501, seasonNumber: 1, name: "Season 1", episodeCount: 2, posterPath: nil),
                    StoredShowSeason(id: 52, traktID: 502, seasonNumber: 2, name: "Season 2", episodeCount: 3, posterPath: nil)
                ])
            )
        )

        let rows = [
            EpisodeRecord(showTMDbID: 500, tmdbID: 50, seasonNumber: 0, episodeNumber: 1, name: "Special", airDate: past),
            EpisodeRecord(showTMDbID: 500, tmdbID: 101, seasonNumber: 1, episodeNumber: 1, name: "Watched", airDate: past),
            EpisodeRecord(showTMDbID: 500, tmdbID: 102, seasonNumber: 1, episodeNumber: 2, name: "Previous One", airDate: past),
            EpisodeRecord(showTMDbID: 500, tmdbID: 201, seasonNumber: 2, episodeNumber: 1, name: "Previous Two", airDate: past),
            EpisodeRecord(showTMDbID: 500, tmdbID: 202, seasonNumber: 2, episodeNumber: 2, name: "Target", airDate: past),
            EpisodeRecord(showTMDbID: 500, tmdbID: 203, seasonNumber: 2, episodeNumber: 3, name: "Future", airDate: future)
        ]
        rows.forEach(context.insert)
        try context.save()

        try await repository.addWatchEvent(for: MediaID(kind: .episode, id: 101, traktID: nil), watchedAt: past)

        let target = EpisodeDetails(
            id: 202,
            traktID: nil,
            showId: 500,
            showTraktID: 5_000,
            seasonNumber: 2,
            episodeNumber: 2,
            name: "Target",
            airDate: past,
            airedAt: nil,
            stillPath: nil,
            overview: nil,
            extras: nil
        )
        let previous = await repository.previousUnwatchedEpisodes(before: target)

        #expect(previous.map(\.tmdbID) == [102, 201])

        try await repository.addWatchEvents(for: previous + [target.mediaID], watchedAt: .now)

        let events = try fetchAll(WatchedEventRecord.self, from: persistence).filter { !$0.tombstoned }
        let operations = try fetchAll(SyncOperationRecord.self, from: persistence)
        #expect(Set(events.map(\.tmdbID)) == [101, 102, 201, 202])
        #expect(operations.filter { $0.kind == .addHistory }.count == 4)
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
    func overlappingSnapshotRefreshesDoNotExposeCancellation() async throws {
        let repository = makeLibraryRepository(persistence: makePersistence())
        let first = Task { try await repository.showLibrarySnapshot(revision: 1, forceRefresh: true) }
        let second = Task { try await repository.showLibrarySnapshot(revision: 1, forceRefresh: true) }
        #expect(try await first.value == .empty)
        #expect(try await second.value == .empty)
        #expect(CancellationError().isCancelled)
    }

    @Test
    func episodeEnrichmentRefreshesCachedImportedProgressWithoutLibraryMutation() async throws {
        let persistence = makePersistence()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProgressCatalogURLProtocol.self]
        let repository = LibraryRepository(
            persistence: persistence,
            tmdb: TMDbService(apiClient: APIClient(session: URLSession(configuration: configuration)), apiKey: "test-key")
        )
        let context = persistence.makeContext()
        let showID = MediaID(kind: .show, id: 515, traktID: 5150)
        context.insert(MediaRecord(
            kind: .show, tmdbID: 515, traktID: 5150, title: "Imported Show",
            overview: "Test show", posterPath: "/show.jpg", totalEpisodes: 2,
            seasonsData: try JSONEncoder().encode([
                StoredShowSeason(id: 1, traktID: nil, seasonNumber: 1, name: "Season 1", episodeCount: 2, posterPath: nil)
            ])
        ))
        context.insert(EpisodeRecord(showTMDbID: 515, tmdbID: 101, seasonNumber: 1, episodeNumber: 1, name: "First", airDate: .distantPast))
        context.insert(WatchedEventRecord(kind: .episode, tmdbID: 101, showTMDbID: 515, seasonNumber: 1, episodeNumber: 1, watchedAt: .now))
        try context.save()

        let before = try await repository.showLibrarySnapshot(revision: 1)
        #expect(before.continueWatching.isEmpty)
        #expect(before.all.first?.needsProgressEnrichment == true)

        try await repository.enrichShowProgress(for: showID)

        // Same library revision: metadata writes must invalidate cached progress.
        let after = try await repository.showLibrarySnapshot(revision: 1)
        #expect(after.continueWatching.first?.progress.nextEpisode?.episode == 2)
        #expect(after.continueWatching.first?.progress.remainingReleased == 1)
        #expect(after.all.first?.needsProgressEnrichment == false)
        #expect(try fetchAll(WatchedEventRecord.self, from: persistence).count == 1)
        #expect(try fetchAll(SyncOperationRecord.self, from: persistence).isEmpty)
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

    @Test(arguments: [false, true])
    func episodeUploadConfirmsMinuteRoundedTime(alreadySent: Bool) async throws {
        let persistence = makePersistence()
        let repository = makeLibraryRepository(persistence: persistence)
        let watched = Date(timeIntervalSince1970: 1700000039.75)
        try await repository.addWatchEvent(for: MediaID(kind: .episode, id: 33, traktID: 333), watchedAt: watched)
        if alreadySent {
            let context = persistence.makeContext()
            let operation = try #require(context.fetch(FetchDescriptor<SyncOperationRecord>()).first)
            var payload = try SyncPayloadCodec.decoder.decode(SyncOperationPayload.self, from: operation.payload)
            payload.historyRequestStartedAt = .now
            payload.historyKnownIDs = []
            operation.payload = try SyncPayloadCodec.encoder.encode(payload)
            try context.save()
        }
        let confirmed = [makeEpisodeHistoryItem(historyID: 999, watchedAt: Date(timeIntervalSince1970: 1699999980))]
        let remote = FakeTraktSyncRemote(token: makeToken(),
            lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now),
            watchlist: [], history: alreadySent ? confirmed : [], historyAfterUpload: confirmed)
        let engine = SyncEngine(persistence: persistence, trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"), accountKeyProvider: { "default" })
        #expect(await engine.run(reason: .localMutation))
        #expect(await remote.snapshot().addHistoryCalls == (alreadySent ? 0 : 1))
        let event = try #require(fetchAll(WatchedEventRecord.self, from: persistence).first)
        #expect(event.traktHistoryID == 999)
        #expect(!event.dirty)
        #expect(event.watchedAt == watched)
    }

    @Test
    func acceptedHistoryUploadWithLostResponseIsNotPostedTwice() async throws {
        let persistence = makePersistence()
        let repository = makeLibraryRepository(persistence: persistence)
        let watched = Date(timeIntervalSince1970: 1700000000.75)
        try await repository.addWatchEvent(for: MediaID(kind: .movie, id: 11, traktID: 111), watchedAt: watched)
        let remote = FakeTraktSyncRemote(token: makeToken(), lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now),
            watchlist: [], history: [], historyAfterUpload: [makeMovieHistoryItem(historyID: 999, watchedAt: Date(timeIntervalSince1970: 1699999980))], loseHistoryResponse: true)
        let engine = SyncEngine(persistence: persistence, trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"), accountKeyProvider: { "default" })
        #expect(await engine.run(reason: .localMutation) == false)
        _ = try await engine.recoverPendingUploads()
        #expect(await engine.run(reason: .localMutation))
        let snapshot = await remote.snapshot()
        #expect(snapshot.addHistoryCalls == 1)
        let events = try fetchAll(WatchedEventRecord.self, from: persistence)
        #expect(events.count == 1)
        #expect(events.first?.traktHistoryID == 999)
        #expect(events.first?.dirty == false)
    }

    @Test
    func existingPlayCannotConfirmANewUncertainUploadInTheSameMinute() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()
        let previous = Date(timeIntervalSince1970: 1700000000)
        context.insert(WatchedEventRecord(kind: .movie, tmdbID: 11, watchedAt: previous, traktHistoryID: 998))
        try context.save()
        let repository = makeLibraryRepository(persistence: persistence)
        try await repository.addWatchEvent(for: MediaID(kind: .movie, id: 11), watchedAt: previous.addingTimeInterval(30.75))
        let existing = [makeMovieHistoryItem(historyID: 998, watchedAt: previous)]
        let remote = FakeTraktSyncRemote(token: makeToken(), lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now),
            watchlist: [], history: existing, historyAfterUpload: existing, loseHistoryResponse: true)
        let engine = SyncEngine(persistence: persistence, trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"), accountKeyProvider: { "default" })
        #expect(await engine.run(reason: .localMutation) == false)
        _ = try await engine.recoverPendingUploads()
        #expect(await engine.run(reason: .localMutation) == false)
        let snapshot = await remote.snapshot()
        #expect(snapshot.addHistoryCalls == 1)
        let events = try fetchAll(WatchedEventRecord.self, from: persistence)
        #expect(events.count == 2)
        #expect(events.contains { $0.traktHistoryID == nil && $0.dirty })
    }

    @Test
    func uncertainHistoryWithoutRemoteEvidenceRemainsUnresolved() async throws {
        let persistence = makePersistence()
        let repository = makeLibraryRepository(persistence: persistence)
        try await repository.addWatchEvent(for: MediaID(kind: .movie, id: 11), watchedAt: .now)
        let context = persistence.makeContext()
        let operation = try #require(context.fetch(FetchDescriptor<SyncOperationRecord>()).first)
        var payload = try SyncPayloadCodec.decoder.decode(SyncOperationPayload.self, from: operation.payload)
        payload.historyRequestStartedAt = .now
        payload.historyKnownIDs = []
        operation.payload = try SyncPayloadCodec.encoder.encode(payload)
        try context.save()
        let remote = FakeTraktSyncRemote(token: makeToken(), lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now), watchlist: [], history: [])
        let engine = SyncEngine(persistence: persistence, trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"), accountKeyProvider: { "default" })
        #expect(await engine.run(reason: .localMutation) == false)
        _ = try await engine.recoverPendingUploads()
        #expect(await engine.run(reason: .localMutation) == false)
        let snapshot = await remote.snapshot()
        #expect(snapshot.addHistoryCalls == 0)
        #expect(try fetchAll(WatchedEventRecord.self, from: persistence).first?.dirty == true)
    }

    @Test(arguments: [false, true])
    func removingPlayDuringUploadDeletesTheRemotePlayAfterConfirmation(lostResponse: Bool) async throws {
        let persistence = makePersistence()
        let repository = makeLibraryRepository(persistence: persistence)
        let watched = Date(timeIntervalSince1970: 1700000000.75)
        try await repository.addWatchEvent(for: MediaID(kind: .movie, id: 11, traktID: 111), watchedAt: watched)
        let eventID = try #require(fetchAll(WatchedEventRecord.self, from: persistence).first?.recordID)
        let remote = FakeTraktSyncRemote(token: makeToken(), lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now),
            watchlist: [], history: [], historyAfterUpload: [makeMovieHistoryItem(historyID: 999, watchedAt: Date(timeIntervalSince1970: 1699999980))],
            loseHistoryResponse: lostResponse,
            onAddHistory: { try await repository.removeWatchEvent(eventID: eventID) })
        let engine = SyncEngine(persistence: persistence, trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"), accountKeyProvider: { "default" })
        let succeeded = await engine.run(reason: .localMutation)
        #expect(succeeded == !lostResponse)
        if lostResponse {
            _ = try await engine.recoverPendingUploads()
            #expect(await engine.run(reason: .localMutation))
        }
        let snapshot = await remote.snapshot()
        #expect(snapshot.addHistoryCalls == 1)
        #expect(snapshot.removeHistoryCalls == 1)
        #expect(try fetchAll(WatchedEventRecord.self, from: persistence).isEmpty)
        #expect(await engine.run(reason: .userInitiated))
        #expect(try fetchAll(WatchedEventRecord.self, from: persistence).isEmpty)
    }

    @Test
    func removingUnsentPlayCancelsItsPendingAddition() async throws {
        let persistence = makePersistence()
        let repository = makeLibraryRepository(persistence: persistence)
        try await repository.addWatchEvent(for: MediaID(kind: .movie, id: 11), watchedAt: .now)
        let eventID = try #require(fetchAll(WatchedEventRecord.self, from: persistence).first?.recordID)
        try await repository.removeWatchEvent(eventID: eventID)
        #expect(try fetchAll(WatchedEventRecord.self, from: persistence).isEmpty)
        #expect(try fetchAll(SyncOperationRecord.self, from: persistence).isEmpty)
    }

    @Test
    func ambiguousRemoteHistoryCannotTriggerAnotherPost() async throws {
        let persistence = makePersistence()
        let repository = makeLibraryRepository(persistence: persistence)
        let watched = Date(timeIntervalSince1970: 1700000000)
        try await repository.addWatchEvent(for: MediaID(kind: .movie, id: 11), watchedAt: watched)
        let context = persistence.makeContext()
        let operation = try #require(context.fetch(FetchDescriptor<SyncOperationRecord>()).first)
        var payload = try SyncPayloadCodec.decoder.decode(SyncOperationPayload.self, from: operation.payload)
        payload.historyRequestStartedAt = .now
        payload.historyKnownIDs = []
        operation.payload = try SyncPayloadCodec.encoder.encode(payload)
        try context.save()
        let remote = FakeTraktSyncRemote(token: makeToken(), lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now),
            watchlist: [], history: [makeMovieHistoryItem(historyID: 998, watchedAt: watched), makeMovieHistoryItem(historyID: 999, watchedAt: watched)])
        let engine = SyncEngine(persistence: persistence, trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"), accountKeyProvider: { "default" })
        #expect(await engine.run(reason: .localMutation) == false)
        let snapshot = await remote.snapshot()
        #expect(snapshot.addHistoryCalls == 0)
        #expect(try fetchAll(SyncOperationRecord.self, from: persistence).first?.status == .deadletter)
        #expect(try fetchAll(WatchedEventRecord.self, from: persistence).count == 2)
    }

    @Test
    func twoRemotePlaysInTheSameSecondArePreserved() async throws {
        let persistence = makePersistence()
        let watched = Date(timeIntervalSince1970: 1700000000)
        let remote = FakeTraktSyncRemote(token: makeToken(), lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now),
            watchlist: [], history: [makeMovieHistoryItem(historyID: 998, watchedAt: watched), makeMovieHistoryItem(historyID: 999, watchedAt: watched)])
        let engine = SyncEngine(persistence: persistence, trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"), accountKeyProvider: { "default" })
        try await engine.ensureInitialBaseline()
        #expect(try fetchAll(WatchedEventRecord.self, from: persistence).count == 2)
    }

    @Test
    func historyReconciliationIsPeriodicButNotTriggeredByLocalEdits() {
        let schedule = HistoryReconciliationSchedule()
        let now = Date()
        let yesterday = now.addingTimeInterval(-86401)
        #expect(!schedule.shouldReconcile(account: "a", reason: .localMutation, previousPull: yesterday, now: now))
        #expect(schedule.shouldReconcile(account: "a", reason: .background, previousPull: yesterday, now: now))
        schedule.recordFullSync(account: "a", now: now)
        #expect(!schedule.shouldReconcile(account: "a", reason: .foreground, previousPull: yesterday, now: now))
        #expect(schedule.shouldReconcile(account: "a", reason: .userInitiated, previousPull: now, now: now))
        #expect(schedule.shouldReconcile(account: "b", reason: .background, previousPull: nil, now: now))
    }

    @Test
    func cloudImportsInvalidateSnapshotsWithoutTrakt() async throws {
        let persistence = makePersistence()
        let remote = FakeTraktSyncRemote(token: nil,
            lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now), watchlist: [], history: [])
        let engine = SyncEngine(persistence: persistence, trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"), accountKeyProvider: { nil })
        let monitor = ActivityTestMonitor()
        var invalidations = 0
        let session = AppSession(
            trakt: TraktService(apiClient: APIClient(session: .shared), clientId: "fixture", clientSecret: "fixture", authStore: InMemoryTraktAuthStore()),
            syncEngine: engine, traktRedirectURI: "com.tyler.iWatch://oauth/callback", cacheService: CacheService(),
            cloudExportMonitor: monitor, invalidateLibrarySnapshots: { invalidations += 1 })
        let date = Date()
        monitor.handler?(.imported(date))
        monitor.handler?(.imported(date))
        for _ in 0..<100 {
            if invalidations > 0 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(invalidations == 1)
        #expect(session.libraryRevision == 1)
        #expect(session.lastCloudImportAt == date)
        #expect(!session.traktConnected)
        monitor.handler?(.exported(date))
        #expect(session.lastCloudExportAt == date)
    }

    @Test
    func repairDoesNotRequeueAnAlreadyAcknowledgedReplica() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()
        let id = UUID()
        for status in [SyncOperationStatus.succeeded, .pending] {
            let operation = SyncOperationRecord(kind: .addWatchlist,
                payload: try SyncPayloadCodec.encoder.encode(SyncOperationPayload(originDeviceID: "device-a", mediaKind: .movie, tmdbID: 42)),
                dedupeKey: "watchlist:movie:42", accountKey: "default", status: status)
            operation.id = id
            context.insert(operation)
        }
        try context.save()
        let engine = SyncEngine(persistence: persistence,
            trakt: FakeTraktSyncRemote(token: nil, lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now), watchlist: [], history: []),
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"), accountKeyProvider: { "default" })
        _ = try await engine.repairIntegrity()
        let operations = try fetchAll(SyncOperationRecord.self, from: persistence)
        #expect(operations.count == 1)
        #expect(operations.first?.status == .succeeded)
    }

    @Test
    func repairPreservesDifferentAccountAndSuccessiveOperations() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()
        for account in ["account-a", "account-b", "account-a"] {
            context.insert(SyncOperationRecord(kind: .addWatchlist,
                payload: try SyncPayloadCodec.encoder.encode(SyncOperationPayload(originDeviceID: "device-a", mediaKind: .movie, tmdbID: 42)),
                dedupeKey: "watchlist:movie:42", accountKey: account))
        }
        try context.save()
        let engine = SyncEngine(persistence: persistence,
            trakt: FakeTraktSyncRemote(token: nil, lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now), watchlist: [], history: []),
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"), accountKeyProvider: { "account-a" })
        _ = try await engine.repairIntegrity()
        #expect(try fetchAll(SyncOperationRecord.self, from: persistence).count == 3)
    }

    @Test
    func pendingOperationsKeepTheirAccountAndDeviceOwnership() async throws {
        let persistence = makePersistence()
        let tmdb = TMDbService(apiClient: APIClient(session: .shared), apiKey: "fixture")
        let a = LibraryRepository(persistence: persistence, tmdb: tmdb,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"), accountKeyProvider: { "account-a" })
        let b = LibraryRepository(persistence: persistence, tmdb: tmdb,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-b"), accountKeyProvider: { "account-b" })
        let movie = MediaID(kind: .movie, id: 42)
        try await a.setWatchlist(true, for: movie)
        try await b.setWatchlist(false, for: movie)
        try await a.setWatchlist(false, for: movie)
        let operations = try fetchAll(SyncOperationRecord.self, from: persistence)
        #expect(operations.count == 2)
        #expect(Set(operations.map(\.accountKey)) == ["account-a", "account-b"])
        let owners = try operations.map { try SyncPayloadCodec.decoder.decode(SyncOperationPayload.self, from: $0.payload).originDeviceID }
        #expect(Set(owners.compactMap { $0 }) == ["device-a", "device-b"])
    }

    @Test(arguments: [nil, "device-b", "device-a"] as [String?])
    func uploadRequiresOriginDeviceAndExplicitRecovery(origin: String?) async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()
        context.insert(SyncOperationRecord(kind: .addWatchlist,
            payload: try SyncPayloadCodec.encoder.encode(SyncOperationPayload(originDeviceID: origin, mediaKind: .movie, tmdbID: 42)),
            accountKey: "default"))
        try context.save()
        let remote = FakeTraktSyncRemote(token: makeToken(),
            lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now), watchlist: [], history: [])
        let engine = SyncEngine(persistence: persistence, trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"), accountKeyProvider: { "default" })
        #expect(await engine.run(reason: .background))
        let before = await remote.snapshot()
        #expect(before.addWatchlistCalls == (origin == "device-a" ? 1 : 0))
        if origin != "device-a" {
            #expect(try await engine.recoverPendingUploads() == 1)
            #expect(await engine.run(reason: .localMutation))
            let after = await remote.snapshot()
            #expect(after.addWatchlistCalls == 1)
        }
    }

    @Test
    func uploadAcknowledgementPreservesNewerLocalEdit() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()
        let movie = MediaID(kind: .movie, id: 42)
        let sentAt = Date()
        context.insert(WatchlistRecord(mediaID: movie, isInWatchlist: true, localUpdatedAt: sentAt, dirty: true))
        context.insert(SyncOperationRecord(kind: .addWatchlist,
            payload: try SyncPayloadCodec.encoder.encode(SyncOperationPayload(originDeviceID: "device-a", mutationAt: sentAt, mediaKind: .movie, tmdbID: 42)),
            accountKey: "default"))
        try context.save()
        let remote = FakeTraktSyncRemote(token: makeToken(),
            lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now), watchlist: [], history: [],
            onAddWatchlist: {
                try await MainActor.run {
                    let edit = persistence.makeContext()
                    let row = try #require(edit.fetch(FetchDescriptor<WatchlistRecord>()).first)
                    row.isInWatchlist = false
                    row.localUpdatedAt = sentAt.addingTimeInterval(1)
                    row.dirty = true
                    try edit.save()
                }
            })
        let engine = SyncEngine(persistence: persistence, trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"), accountKeyProvider: { "default" })
        #expect(await engine.run(reason: .background))
        let row = try #require(fetchAll(WatchlistRecord.self, from: persistence).first)
        #expect(!row.isInWatchlist)
        #expect(row.dirty)
    }

    @Test
    func operationDatesDecodeLegacyAndPreserveMutationPrecision() throws {
        let legacy = Data(#"{"mediaKind":"movie","tmdbID":42,"watchedAt":"2026-10-25T10:00:00Z"}"#.utf8)
        let decoded = try SyncPayloadCodec.decoder.decode(SyncOperationPayload.self, from: legacy)
        #expect(decoded.watchedAt != nil)
        #expect(decoded.originDeviceID == nil)
        let now = Date(timeIntervalSince1970: 12345.123456)
        let payload = SyncOperationPayload(mutationAt: now)
        let restored = try SyncPayloadCodec.decoder.decode(SyncOperationPayload.self, from: SyncPayloadCodec.encoder.encode(payload))
        #expect(restored.mutationAt == now)
    }

    @Test
    func metadataFreshnessExpiresIndependentlyOfLibraryUpdates() throws {
        let suite = "iWatch.freshness.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MetadataFreshnessStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 10000)
        #expect(store.needsRefresh("show:42", after: 3600, now: now))
        store.markFetched("show:42", now: now)
        #expect(!store.needsRefresh("show:42", after: 3600, now: now.addingTimeInterval(3599)))
        #expect(store.needsRefresh("show:42", after: 3600, now: now.addingTimeInterval(3600)))
        store.clear()
        #expect(store.needsRefresh("show:42", after: 3600, now: now))
    }

    @Test
    func diagnosticFormattingRedactsPrivateValues() throws {
        let url = try #require(URL(string: "https://example.com/search?api_key=private&query=private#private"))
        #expect(redactedRequestURL(url) == "https://example.com/search")
        let nested = NSError(domain: CKErrorDomain, code: CKError.quotaExceeded.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "private server details"])
        let error = NSError(domain: CKErrorDomain, code: CKError.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: ["private-record": nested]])
        let summary = CloudKitExportMonitor.errorSummary(error)
        #expect(summary.contains("storage"))
        #expect(!summary.contains("private"))
    }

    // MARK: Incremental Sync

    @Test
    func outboxClaimPreventsDoublePushAcrossEngines() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()
        let mediaID = MediaID(kind: .movie, id: 11, traktID: 111)

        context.insert(WatchlistRecord(mediaID: mediaID, isInWatchlist: true, dirty: true))
        context.insert(SyncStateRecord(accountKey: "default", initialBaselineComplete: true))
        context.insert(
            SyncOperationRecord(
                kind: .addWatchlist,
                payload: try SyncPayloadCodec.encoder.encode(
                    SyncOperationPayload(originDeviceID: "device-a", mediaKind: .movie, tmdbID: 11, traktID: 111)
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
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"),
            accountKeyProvider: { "default" }
        )
        let engineB = SyncEngine(
            persistence: persistence,
            trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-b"),
            accountKeyProvider: { "default" }
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
    func syncStateIsSelectedForEachAccount() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()
        let recent = Date()
        context.insert(SyncStateRecord(
            accountKey: "account-a", initialBaselineComplete: true,
            lastSuccessfulPullAt: recent, lastSuccessfulPushAt: recent
        ))
        try context.save()
        let remote = FakeTraktSyncRemote(
            token: makeToken(), lastActivities: makeLastActivities(watchlistAt: recent, historyAt: recent),
            watchlist: [], history: []
        )
        let engineA = SyncEngine(
            persistence: persistence, trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"),
            accountKeyProvider: { "account-a" }
        )
        let engineB = SyncEngine(
            persistence: persistence, trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"),
            accountKeyProvider: { "account-b" }
        )
        let snapshotA = await engineA.snapshot()
        let snapshotB = await engineB.snapshot()
        #expect(snapshotA.initialBaselineComplete)
        #expect(snapshotA.lastSuccessfulPullAt == recent)
        #expect(!snapshotB.initialBaselineComplete)
        #expect(snapshotB.lastSuccessfulPullAt == nil)
        #expect(await engineA.shouldRefreshOnForeground(maxStaleness: 3600) == false)
        #expect(await engineB.shouldRefreshOnForeground(maxStaleness: 3600))
    }

    @Test(arguments: [nil, "account-b"] as [String?])
    func outboxUploadsOnlyForSelectedAccount(accountKey: String?) async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()
        for (index, owner) in ["account-a", "account-b", ""].enumerated() {
            context.insert(SyncOperationRecord(
                kind: .addWatchlist,
                payload: try SyncPayloadCodec.encoder.encode(
                    SyncOperationPayload(originDeviceID: "device-a", mediaKind: .movie, tmdbID: index + 1, traktID: index + 1)
                ),
                dedupeKey: "watchlist:movie:\(index + 1)", accountKey: owner
            ))
        }
        try context.save()
        let remote = FakeTraktSyncRemote(
            token: makeToken(), lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now),
            watchlist: [], history: []
        )
        let engine = SyncEngine(
            persistence: persistence, trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"),
            accountKeyProvider: { accountKey }
        )
        #expect(await engine.run(reason: .background))
        let snapshot = await remote.snapshot()
        let operations = try fetchAll(SyncOperationRecord.self, from: persistence)
        #expect(operations.count == 3)
        #expect(snapshot.addWatchlistCalls == (accountKey == nil ? 0 : 1))
        for operation in operations {
            #expect(operation.status == (operation.accountKey == accountKey ? .succeeded : .pending))
        }
    }

    @Test
    func foregroundRefreshRunsWhenOutboxHasPendingOperations() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()

        context.insert(
            SyncOperationRecord(
                kind: .addWatchlist,
                payload: try SyncPayloadCodec.encoder.encode(
                    SyncOperationPayload(originDeviceID: "device-a", mediaKind: .movie, tmdbID: 11, traktID: 111)
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
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"),
            accountKeyProvider: { "default" }
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
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"),
            accountKeyProvider: { "default" }
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
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"),
            accountKeyProvider: { "default" }
        )

        let succeeded = await engine.run(reason: .foreground)
        let snapshot = await remote.snapshot()

        #expect(succeeded == true)
        #expect(snapshot.getLastActivitiesCalls == 1)
        #expect(snapshot.getWatchlistCalls == 0)
        #expect(snapshot.getHistoryCalls == 0)
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
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"),
            accountKeyProvider: { "default" }
        )

        let succeeded = await engine.run(reason: .foreground)
        let rows = try fetchAll(WatchlistRecord.self, from: persistence)

        #expect(succeeded == true)
        #expect(rows.count == 1)
        #expect(rows[0].isInWatchlist == false)
        #expect(rows[0].dirty == false)
    }

    @Test
    func userInitiatedSyncReconcilesRemoteHistoryDeletions() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()
        let oldActivity = Date().addingTimeInterval(-3_600)
        context.insert(WatchedEventRecord(
            kind: .movie,
            tmdbID: 12,
            traktID: 112,
            watchedAt: oldActivity,
            traktHistoryID: 7_002
        ))
        context.insert(WatchedEventRecord(
            kind: .movie,
            tmdbID: 11,
            traktID: 111,
            watchedAt: oldActivity.addingTimeInterval(-60),
            traktHistoryID: 7_001
        ))
        context.insert(WatchedEventRecord(
            kind: .movie,
            tmdbID: 13,
            traktID: 113,
            watchedAt: oldActivity,
            dirty: true
        ))
        context.insert(SyncStateRecord(
            accountKey: "default",
            initialBaselineComplete: true,
            lastSuccessfulPullAt: oldActivity,
            lastSuccessfulPushAt: oldActivity,
            lastSeenRemoteActivityAt: oldActivity
        ))
        try context.save()

        let engine = SyncEngine(
            persistence: persistence,
            trakt: FakeTraktSyncRemote(
                token: makeToken(),
                lastActivities: makeLastActivities(
                    watchlistAt: oldActivity,
                    historyAt: oldActivity
                ),
                watchlist: [],
                history: [makeMovieHistoryItem(
                    historyID: 7_001,
                    watchedAt: oldActivity.addingTimeInterval(-60)
                )]
            ),
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"),
            accountKeyProvider: { "default" }
        )

        #expect(await engine.run(reason: .userInitiated) == true)
        let events = try fetchAll(WatchedEventRecord.self, from: persistence)
        #expect(events.first(where: { $0.traktHistoryID == 7_002 })?.tombstoned == true)
        #expect(events.first(where: { $0.traktHistoryID == 7_001 })?.tombstoned == false)
        #expect(events.first(where: { $0.tmdbID == 13 })?.tombstoned == false)
    }

    @Test
    func emptyRemoteHistoryPayloadCannotEraseExistingHistory() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()
        let oldActivity = Date().addingTimeInterval(-3_600)
        context.insert(WatchedEventRecord(
            kind: .movie,
            tmdbID: 11,
            traktID: 111,
            watchedAt: oldActivity,
            traktHistoryID: 7_001
        ))
        context.insert(SyncStateRecord(
            accountKey: "default",
            initialBaselineComplete: true,
            lastSuccessfulPullAt: oldActivity,
            lastSuccessfulPushAt: oldActivity,
            lastSeenRemoteActivityAt: oldActivity
        ))
        try context.save()

        let engine = SyncEngine(
            persistence: persistence,
            trakt: FakeTraktSyncRemote(
                token: makeToken(),
                lastActivities: makeLastActivities(watchlistAt: oldActivity, historyAt: oldActivity),
                watchlist: [],
                history: []
            ),
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"),
            accountKeyProvider: { "default" }
        )

        #expect(await engine.run(reason: .userInitiated) == true)
        #expect(try #require(fetchAll(WatchedEventRecord.self, from: persistence).first).tombstoned == false)
    }

    @Test
    func activeTraktProgressUsesHistoryWithoutCreatingWatchlistMembership() async throws {
        let persistence = makePersistence()
        let remote = FakeTraktSyncRemote(
            token: makeToken(),
            lastActivities: makeLastActivities(watchlistAt: .now, historyAt: .now),
            watchlist: [],
            history: [makeEpisodeHistoryItem(historyID: 8001, watchedAt: .now)]
        )
        let engine = SyncEngine(
            persistence: persistence,
            trakt: remote,
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"),
            accountKeyProvider: { "default" }
        )

        try await engine.ensureInitialBaseline()

        let rows = try fetchAll(WatchlistRecord.self, from: persistence)
        #expect(rows.isEmpty)
        #expect(try fetchAll(WatchedEventRecord.self, from: persistence).count == 1)
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
                history: [makeEpisodeHistoryItem(historyID: 8001, watchedAt: .now)]
            ),
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"),
            accountKeyProvider: { "default" }
        )

        try await engine.ensureInitialBaseline()

        let rows = try fetchAll(WatchlistRecord.self, from: persistence)
        #expect(rows.count == 1)
        #expect(rows[0].isInWatchlist == false)
    }

    @Test
    func watchedItemLeavesWatchlistAfterTraktAutoRemovesIt() async throws {
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
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"),
            accountKeyProvider: { "default" }
        )

        #expect(await engine.run(reason: .foreground) == true)
        let rows = try fetchAll(WatchlistRecord.self, from: persistence)
        #expect(rows.count == 1)
        #expect(rows[0].isInWatchlist == false)
    }

    // MARK: Repair and Persistence

    @Test
    func retryDeadletterOperationsRequeuesFailedWork() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()

        context.insert(
            SyncOperationRecord(
                kind: .addWatchlist,
                payload: try SyncPayloadCodec.encoder.encode(
                    SyncOperationPayload(originDeviceID: "device-a", mediaKind: .movie, tmdbID: 11, traktID: 111)
                ),
                dedupeKey: "watchlist:movie:11",
                accountKey: "default",
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
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"),
            accountKeyProvider: { "default" }
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
        context.insert(MediaRecord(kind: .movie, tmdbID: 11, traktID: 111, title: "",
            updatedAt: watchedAt.addingTimeInterval(-10 * 86400)))
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
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"),
            accountKeyProvider: { "default" }
        )

        let summary = try await engine.repairIntegrity()

        #expect(summary.mediaMerged == 1)
        #expect(try fetchAll(MediaRecord.self, from: persistence).first?.metadataCachedAt == watchedAt.addingTimeInterval(-10 * 86400))
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
                payload: try SyncPayloadCodec.encoder.encode(SyncOperationPayload(originDeviceID: "device-a", mediaKind: .movie, tmdbID: 1, traktID: 10))
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
    func movieLibraryIncludesWatchlistAndHistoryOnlyItems() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()
        let earlier = Date(timeIntervalSince1970: 1_000)
        let later = Date(timeIntervalSince1970: 2_000)

        context.insert(MediaRecord(kind: .movie, tmdbID: 1, traktID: 10, title: "Saved"))
        context.insert(MediaRecord(kind: .movie, tmdbID: 2, traktID: 20, title: "Watched"))
        context.insert(WatchlistRecord(mediaID: MediaID(kind: .movie, id: 1, traktID: 10), isInWatchlist: true))
        context.insert(WatchedEventRecord(kind: .movie, tmdbID: 2, traktID: 20, watchedAt: earlier))
        context.insert(WatchedEventRecord(kind: .movie, tmdbID: 2, traktID: 20, watchedAt: later))
        try context.save()

        let items = try await LibrarySnapshotReader(persistence: persistence).movieItems()
        let saved = try #require(items.first { $0.id == 1 })
        let watched = try #require(items.first { $0.id == 2 })

        #expect(saved.isInWatchlist)
        #expect(!saved.isWatched)
        #expect(!watched.isInWatchlist)
        #expect(watched.isWatched)
        #expect(watched.lastWatchedAt == later)
    }

    @Test
    func showLibraryIncludesHistoryOnlyItems() async throws {
        let persistence = makePersistence()
        let context = persistence.makeContext()
        context.insert(MediaRecord(
            kind: .show,
            tmdbID: 3,
            traktID: 30,
            title: "Finished",
            totalEpisodes: 1,
            statusRaw: "Ended"
        ))
        context.insert(EpisodeRecord(
            showTMDbID: 3,
            showTraktID: 30,
            tmdbID: 31,
            traktID: 310,
            seasonNumber: 1,
            episodeNumber: 1,
            name: "Finale",
            airDate: Date(timeIntervalSince1970: 1_000)
        ))
        context.insert(WatchedEventRecord(
            kind: .episode,
            tmdbID: 31,
            traktID: 310,
            showTMDbID: 3,
            showTraktID: 30,
            seasonNumber: 1,
            episodeNumber: 1,
            watchedAt: Date(timeIntervalSince1970: 2_000)
        ))
        try context.save()

        let items = try await LibrarySnapshotReader(persistence: persistence).showItems()
        let item = try #require(items.first)

        #expect(item.mediaID == MediaID(kind: .show, id: 3, traktID: 30))
        #expect(item.progress.isComplete)
        #expect(item.status.bucket == .ended)
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
                payload: try SyncPayloadCodec.encoder.encode(SyncOperationPayload(originDeviceID: "device-a", mediaKind: .movie, tmdbID: 1, traktID: 10))
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
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"),
            accountKeyProvider: { "default" }
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
            deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"),
            accountKeyProvider: { "default" }
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

}

// MARK: - Fixtures

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
    return LibraryRepository(persistence: persistence, tmdb: tmdb, resetGate: resetGate,
        deviceIdentityStore: FixedDeviceIdentityStore(id: "device-a"), accountKeyProvider: { "default" })
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

private func makeLastActivities(
    watchlistAt: Date?,
    historyAt: Date?
) -> TraktLastActivitiesDTO {
    TraktLastActivitiesDTO(
        all: [watchlistAt, historyAt].compactMap { $0 }.max(),
        movies: TraktActivityGroupDTO(watchedAt: historyAt, watchlistedAt: watchlistAt),
        episodes: TraktActivityGroupDTO(watchedAt: historyAt, watchlistedAt: nil),
        shows: TraktActivityGroupDTO(watchedAt: nil, watchlistedAt: watchlistAt),
        watchlist: TraktActivityTimestampDTO(updatedAt: watchlistAt)
    )
}

// MARK: - Test Doubles

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
        let addWatchlistCalls: Int
        let removeWatchlistCalls: Int
        let addHistoryCalls: Int
        let removeHistoryCalls: Int
    }

    private let token: TokenResponse?
    private let lastActivities: TraktLastActivitiesDTO
    private let watchlist: [TraktWatchlistItemDTO]
    private var history: [TraktHistoryItemDTO]
    private let historyAfterUpload: [TraktHistoryItemDTO]?
    private var loseHistoryResponse: Bool
    private let onAddHistory: (@Sendable () async throws -> Void)?
    private let addWatchlistDelayNanos: UInt64
    private let onAddWatchlist: (@Sendable () async throws -> Void)?

    private var getLastActivitiesCalls = 0
    private var getWatchlistCalls = 0
    private var getHistoryCalls = 0
    private var addWatchlistCalls = 0
    private var removeWatchlistCalls = 0
    private var addHistoryCalls = 0
    private var removeHistoryCalls = 0

    init(token: TokenResponse?,
         lastActivities: TraktLastActivitiesDTO,
         watchlist: [TraktWatchlistItemDTO],
         history: [TraktHistoryItemDTO],
         addWatchlistDelayNanos: UInt64 = 0,
         onAddWatchlist: (@Sendable () async throws -> Void)? = nil,
         historyAfterUpload: [TraktHistoryItemDTO]? = nil,
         loseHistoryResponse: Bool = false,
         onAddHistory: (@Sendable () async throws -> Void)? = nil) {
        self.token = token
        self.lastActivities = lastActivities
        self.watchlist = watchlist
        self.history = history
        self.addWatchlistDelayNanos = addWatchlistDelayNanos
        self.onAddWatchlist = onAddWatchlist
        self.historyAfterUpload = historyAfterUpload
        self.loseHistoryResponse = loseHistoryResponse
        self.onAddHistory = onAddHistory
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
        let snapshot = history
        return await MainActor.run {
            snapshot.filter { item in
                guard let startAt else { return true }
                return item.watchedAt.map { $0 >= startAt } ?? false
            }
        }
    }

    func addToWatchlist(_ items: [MediaID]) async throws {
        addWatchlistCalls += 1
        try await onAddWatchlist?()
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
        if let historyAfterUpload { history = historyAfterUpload }
        try await onAddHistory?()
        if loseHistoryResponse { loseHistoryResponse = false; throw URLError(.timedOut) }
        #expect(payloads.isEmpty == false)
    }

    func removeFromHistory(historyIDs: [Int]) async throws {
        removeHistoryCalls += 1
        let snapshot = history
        let ids = await MainActor.run { snapshot.map(\.id) }
        history = zip(snapshot, ids).filter { !historyIDs.contains($0.1) }.map { $0.0 }
        #expect(historyIDs.isEmpty == false)
    }

    func snapshot() -> Snapshot {
        Snapshot(
            getLastActivitiesCalls: getLastActivitiesCalls,
            getWatchlistCalls: getWatchlistCalls,
            getHistoryCalls: getHistoryCalls,
            addWatchlistCalls: addWatchlistCalls,
            removeWatchlistCalls: removeWatchlistCalls,
            addHistoryCalls: addHistoryCalls,
            removeHistoryCalls: removeHistoryCalls
        )
    }
}

private final class ProgressCatalogURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.url?.path == "/3/tv/515/season/1" else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let data = #"{"id":1,"season_number":1,"name":"Season 1","episodes":[{"id":101,"season_number":1,"episode_number":1,"name":"First","air_date":"2020-01-01"},{"id":102,"season_number":1,"episode_number":2,"name":"Second","air_date":"2020-01-02"}]}"#.data(using: .utf8)!
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
private final class ActivityTestMonitor: CloudExportMonitoring {
    var handler: (@MainActor (CloudStoreActivity) -> Void)?
    func observeActivity(_ handler: @escaping @MainActor (CloudStoreActivity) -> Void) { self.handler = handler }
    func waitForExport(startingAfter date: Date, timeout: Duration) async -> CloudExportConfirmation { .completed(date) }
}
