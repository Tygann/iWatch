import Foundation
import SwiftData

// MARK: - Library Repository

@MainActor
final class LibraryRepository {
    private let persistence: Persistence
    private let tmdb: TMDbService
    private let airtimeProvider: (any EpisodeAirtimeProviding)?
    private let resetGate: AppDataResetGate
    private let deviceIdentityStore: any DeviceIdentityStore
    private let accountKeyProvider: @Sendable () -> String?
    private let snapshotReader: LibrarySnapshotReader
    private var cachedMovieSnapshot: (revision: Int, cachedAt: Date, items: [LibraryMovieItem])?
    private var cachedShowSnapshot: (revision: Int, cachedAt: Date, snapshot: ShowLibrarySnapshot)?
    private var showSnapshotTask: (revision: Int, token: UUID, task: Task<ShowLibrarySnapshot, Error>)?
    private var detailRequests: [String: Task<MediaDetails, Error>] = [:]
    private let metadataFreshness: MetadataFreshnessStore
    private var refreshedSeasonArtworkKeys: Set<String> = []

    init(
        persistence: Persistence,
        tmdb: TMDbService,
        airtimeProvider: (any EpisodeAirtimeProviding)? = nil,
        resetGate: AppDataResetGate = AppDataResetGate(),
        deviceIdentityStore: any DeviceIdentityStore = KeychainDeviceIdentityStore(),
        accountKeyProvider: @escaping @Sendable () -> String? = { TraktLinkStore.activeAccountKey },
        metadataFreshness: MetadataFreshnessStore? = nil
    ) {
        self.persistence = persistence
        self.tmdb = tmdb
        self.airtimeProvider = airtimeProvider
        self.resetGate = resetGate
        self.deviceIdentityStore = deviceIdentityStore
        self.accountKeyProvider = accountKeyProvider
        self.metadataFreshness = metadataFreshness ?? MetadataFreshnessStore()
        self.snapshotReader = LibrarySnapshotReader(persistence: persistence)
    }

    var onMetadataChanged: (@MainActor () -> Void)?

    func invalidateSnapshots() {
        cachedMovieSnapshot = nil
        cachedShowSnapshot = nil
        showSnapshotTask?.task.cancel()
        showSnapshotTask = nil
    }

    func expireProviderMetadata() throws {
        _ = try persistence.makeMetadataContext()
        invalidateSnapshots()
    }

    // MARK: Discovery

    func search(query: String) async throws -> [SearchItem] {
        let items = try await tmdb.search(query: query)
        try cacheSearchItems(items)
        return items
    }

    func trending(kind: MediaKind) async throws -> [SearchItem] {
        let items = try await tmdb.trending(kind: kind)
        try cacheSearchItems(items)
        return items
    }

    func mixedTrending() async throws -> [SearchItem] {
        let items = try await tmdb.mixedTrending()
        try cacheSearchItems(items)
        return items
    }

    func discovery(kind: MediaKind, collection: DiscoveryCollection) async throws -> [SearchItem] {
        let items = try await tmdb.discovery(kind: kind, collection: collection)
        try cacheSearchItems(items)
        return items
    }

    func watchProviders(kind: MediaKind, regionCode: String) async throws -> [DiscoveryProvider] {
        try await tmdb.watchProviders(kind: kind, regionCode: regionCode)
    }

    func watchProviders(regionCode: String) async throws -> [DiscoveryProvider] {
        try await tmdb.watchProviders(regionCode: regionCode)
    }

    func discover(
        kind: MediaKind,
        providerID: Int,
        offerType: ProviderOfferType,
        regionCode: String
    ) async throws -> [SearchItem] {
        let items = try await tmdb.discover(
            kind: kind,
            providerID: providerID,
            offerType: offerType,
            regionCode: regionCode
        )
        try cacheSearchItems(items)
        return items
    }

    // MARK: Details

    func mediaDetails(for id: MediaID, forceRefresh: Bool = false) async throws -> MediaDetails {
        let context = try persistence.makeMetadataContext()
        if !forceRefresh, let record = mediaRecord(for: id, context: context), isMediaRecordComplete(record) {
            let cached = try mapMediaRecord(record)
            let upcoming = record.releaseDate.map { $0 > Date() } ?? false
            let ended = ["ended", "canceled", "cancelled"].contains(record.statusRaw?.lowercased() ?? "")
            let interval: TimeInterval = upcoming ? 6 * 3600 : (id.kind == .show && !ended ? 12 * 3600 : 7 * 86400)
            if metadataFreshness.needsRefresh(id.stableKey, after: interval) {
                Task { [weak self] in _ = try? await self?.refreshMediaDetails(for: id) }
            }
            return cached
        }
        return try await refreshMediaDetails(for: id)
    }

    private func refreshMediaDetails(for id: MediaID) async throws -> MediaDetails {
        if let request = detailRequests[id.stableKey] { return try await request.value }
        metadataFreshness.markAttempt(id.stableKey)
        let request = Task { try await self.fetchMediaDetails(for: id) }
        detailRequests[id.stableKey] = request
        defer { detailRequests[id.stableKey] = nil }
        let details = try await request.value
        metadataFreshness.markFetched(id.stableKey)
        onMetadataChanged?()
        return details
    }

    private func fetchMediaDetails(for id: MediaID) async throws -> MediaDetails {
        switch id.kind {
        case .movie:
            let fresh = try await tmdb.movieDetails(id: id.tmdbID)
            let mapped = TMDbMappers.movie(fresh)
            try upsertMovie(mapped, requestedID: id)
            return .movie(merged(mapped, requestedID: id))
        case .show:
            let fresh = try await tmdb.showDetails(id: id.tmdbID)
            let mapped = TMDbMappers.show(fresh)
            try upsertShow(mapped, requestedID: id)
            return .show(merged(mapped, requestedID: id))
        case .episode:
            throw AppError.featureNotImplemented("Use episodeDetails(for:) for episodes.")
        case .person:
            throw AppError.featureNotImplemented("People are not part of the v2 foundation.")
        }
    }

    func supplementaryDetails(for id: MediaID, regionCode: String) async throws -> MediaSupplementaryDetails {
        try await tmdb.supplementaryDetails(for: id, regionCode: regionCode)
    }

    func episodes(for showID: MediaID, seasonNumber: Int, forceRefresh: Bool = false) async throws -> [EpisodeDetails] {
        let context = try persistence.makeMetadataContext()
        let cached = episodeRecords(forShowID: showID.tmdbID, seasonNumber: seasonNumber, context: context)
        let expectedEpisodeCount = mediaRecord(for: showID, context: context)
            .flatMap { decodeSeasons($0.seasonsData) }
            .flatMap { seasons in
                seasons.first { $0.seasonNumber == seasonNumber }?.episodeCount
            }
        let seasonKey = "\(showID.tmdbID):\(seasonNumber)"
        let shouldRefresh = EpisodeSeasonCachePolicy.shouldRefresh(
            cachedCount: cached.count,
            expectedEpisodeCount: expectedEpisodeCount,
            hasMissingArtwork: cached.contains { $0.stillPath == nil },
            attemptedArtworkRefresh: refreshedSeasonArtworkKeys.contains(seasonKey)
        )

        if !forceRefresh, !shouldRefresh, !metadataFreshness.needsRefresh("season:\(seasonKey)", after: 12 * 3600) {
            return cached.map(mapEpisodeRecord(_:))
        }

        let fresh: [EpisodeDetails]
        do { fresh = try await tmdb.seasonEpisodes(showId: showID.tmdbID, seasonNumber: seasonNumber) }
        catch {
            if !forceRefresh, !cached.isEmpty { return cached.map(mapEpisodeRecord(_:)) }
            throw error
        }
        let enriched = await enrichingEpisodesWithAirtimes(fresh, showID: showID, seasonNumber: seasonNumber)
        try upsertEpisodes(enriched, for: showID)
        refreshedSeasonArtworkKeys.insert(seasonKey)
        metadataFreshness.markFetched("season:\(seasonKey)")

        let refreshedContext = try persistence.makeMetadataContext()
        return episodeRecords(forShowID: showID.tmdbID, seasonNumber: seasonNumber, context: refreshedContext)
            .map(mapEpisodeRecord(_:))
    }

    func episodeDetails(for ref: EpisodeRef, forceRefresh: Bool = false) async throws -> EpisodeDetails {
        let context = try persistence.makeMetadataContext()
        if !forceRefresh,
           let record = episodeRecord(for: ref, context: context) {
            let cached = mapEpisodeRecord(record)
            if hasRichEpisodeDetails(cached) {
                let resource = "episode:\(ref.showId):\(ref.season):\(ref.episode)"
                if metadataFreshness.needsRefresh(resource, after: 12 * 3600) {
                    metadataFreshness.markAttempt(resource)
                    Task { [weak self] in _ = try? await self?.episodeDetails(for: ref, forceRefresh: true) }
                }
                guard cached.airedAt == nil else { return cached }
                let enriched = await enrichingEpisodeWithAirtime(cached, ref: ref)
                if enriched != cached {
                    try upsertEpisodes(
                        [enriched],
                        for: MediaID(kind: .show, id: ref.showId, traktID: ref.showTraktID)
                    )
                }
                return enriched
            }
        }

        var fresh = try await tmdb.episodeDetails(
            showId: ref.showId,
            seasonNumber: ref.season,
            episodeNumber: ref.episode
        )
        fresh = await enrichingEpisodeWithAirtime(fresh, ref: ref)
        try upsertEpisodes([fresh], for: MediaID(kind: .show, id: ref.showId, traktID: ref.showTraktID))
        metadataFreshness.markFetched("episode:\(ref.showId):\(ref.season):\(ref.episode)")
        onMetadataChanged?()

        let refreshedContext = try persistence.makeMetadataContext()
        guard let record = episodeRecord(for: ref, context: refreshedContext) else {
            throw AppError.unknown("Unable to cache episode details.")
        }
        return mapEpisodeRecord(record)
    }

    private func hasRichEpisodeDetails(_ episode: EpisodeDetails) -> Bool {
        guard let extras = episode.extras else { return false }

        return !extras.cast.isEmpty
            || !extras.guestStars.isEmpty
            || !extras.crew.isEmpty
            || !extras.images.isEmpty
            || !extras.videos.isEmpty
            || extras.externalIDs.imdb != nil
            || extras.externalIDs.tvdb != nil
    }

    private func enrichingEpisodesWithAirtimes(
        _ episodes: [EpisodeDetails],
        showID: MediaID,
        seasonNumber: Int
    ) async -> [EpisodeDetails] {
        guard let airtimeProvider, let showTraktID = showID.traktID else { return episodes }
        guard let airtimes = try? await airtimeProvider.seasonAirtimes(
            showTraktID: showTraktID,
            seasonNumber: seasonNumber
        ) else { return episodes }

        let byEpisodeNumber = airtimes.reduce(into: [Int: EpisodeAirtime]()) {
            $0[$1.episodeNumber] = $1
        }
        return episodes.map { episode in
            guard let airtime = byEpisodeNumber[episode.episodeNumber] else { return episode }
            return episode.merging(airtime: airtime, showTraktID: showTraktID)
        }
    }

    private func enrichingEpisodeWithAirtime(_ episode: EpisodeDetails, ref: EpisodeRef) async -> EpisodeDetails {
        guard let airtimeProvider, let traktID = ref.traktID,
              let airtime = try? await airtimeProvider.episodeAirtime(traktID: traktID) else {
            return episode
        }
        return episode.merging(airtime: airtime, showTraktID: ref.showTraktID)
    }

    // MARK: Library Mutations

    func setWatchlist(_ inWatchlist: Bool, for id: MediaID) async throws {
        let deviceID = await deviceIdentityStore.currentDeviceID()
        guard await resetGate.allowsLibraryWork() else {
            throw AppError.unknown("Wait for the library reset to finish before making changes.")
        }
        let context = try persistence.makeMetadataContext()
        let now = Date()
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)

        let existing = watchlistRecord(for: id, context: context)
        let record = existing ?? WatchlistRecord(
            mediaID: id,
            isInWatchlist: inWatchlist,
            localUpdatedAt: now,
            dirty: true,
            generationID: generationID
        )
        if existing == nil {
            context.insert(record)
        }

        record.traktID = id.traktID ?? record.traktID
        record.isInWatchlist = inWatchlist
        record.localUpdatedAt = now
        record.dirty = true

        let payload = SyncOperationPayload(mediaKind: id.kind,
                                           tmdbID: id.tmdbID,
                                           traktID: id.traktID,
                                           showTMDbID: nil,
                                           showTraktID: nil,
                                           seasonNumber: nil,
                                           episodeNumber: nil,
                                           watchedAt: nil,
                                           historyID: nil)
        try upsertSyncOperation(
            kind: inWatchlist ? .addWatchlist : .removeWatchlist,
            payload: payload,
            dedupeKey: "watchlist:\(id.stableKey)",
            context: context, accountKey: accountKeyProvider() ?? "", deviceID: deviceID
        )

        if inWatchlist, id.kind == .show {
            setShowDisposition(.active, for: id, context: context, now: now)
        }

        try context.save()
    }

    func addWatchEvent(for id: MediaID, watchedAt: Date) async throws {
        try await addWatchEvents(for: [id], watchedAt: watchedAt)
    }

    func addWatchEvents(for ids: [MediaID], watchedAt: Date) async throws {
        let deviceID = await deviceIdentityStore.currentDeviceID()
        guard await resetGate.allowsLibraryWork() else {
            throw AppError.unknown("Wait for the library reset to finish before making changes.")
        }
        let context = try persistence.makeMetadataContext()
        let now = Date()
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)

        for id in ids {
            let episodeMetadata = id.kind == .episode ? episodeRecord(forTMDbID: id.tmdbID, context: context) : nil
            let eventKey = WatchedEventRecord.makeEventKey(
                kind: id.kind,
                tmdbID: id.tmdbID,
                traktID: id.traktID,
                watchedAt: watchedAt
            )
            if watchedEventRecord(forEventKey: eventKey, context: context) != nil {
                continue
            }

            let event = WatchedEventRecord(
                kind: id.kind,
                tmdbID: id.tmdbID,
                traktID: id.traktID,
                showTMDbID: episodeMetadata?.showTMDbID,
                showTraktID: episodeMetadata?.showTraktID,
                seasonNumber: episodeMetadata?.seasonNumber,
                episodeNumber: episodeMetadata?.episodeNumber,
                watchedAt: watchedAt,
                dirty: true,
                tombstoned: false,
                createdAt: now,
                updatedAt: now,
                generationID: generationID
            )
            context.insert(event)

            let payload = SyncOperationPayload(
                mediaKind: id.kind,
                tmdbID: id.tmdbID,
                traktID: id.traktID,
                showTMDbID: episodeMetadata?.showTMDbID,
                showTraktID: episodeMetadata?.showTraktID,
                seasonNumber: episodeMetadata?.seasonNumber,
                episodeNumber: episodeMetadata?.episodeNumber,
                watchedAt: watchedAt,
                historyID: nil
            )
            try upsertSyncOperation(
                kind: .addHistory,
                payload: payload,
                dedupeKey: "history:add:\(eventKey)",
                context: context, accountKey: accountKeyProvider() ?? "", deviceID: deviceID
            )

            let planToWatchID: MediaID? = switch id.kind {
            case .movie:
                id
            case .episode:
                episodeMetadata.map {
                    MediaID(kind: .show, id: $0.showTMDbID, traktID: $0.showTraktID)
                }
            default:
                nil
            }

            if let planToWatchID,
               let watchlist = watchlistRecord(for: planToWatchID, context: context),
               watchlist.isInWatchlist {
                watchlist.isInWatchlist = false
                watchlist.localUpdatedAt = now
                watchlist.dirty = true
                let watchlistPayload = SyncOperationPayload(
                    mediaKind: planToWatchID.kind,
                    tmdbID: planToWatchID.tmdbID,
                    traktID: planToWatchID.traktID,
                    showTMDbID: nil,
                    showTraktID: nil,
                    seasonNumber: nil,
                    episodeNumber: nil,
                    watchedAt: nil,
                    historyID: nil
                )
                try upsertSyncOperation(
                    kind: .removeWatchlist,
                    payload: watchlistPayload,
                    dedupeKey: "watchlist:\(planToWatchID.stableKey)",
                    context: context,
                    accountKey: accountKeyProvider() ?? "", deviceID: deviceID
                )
            }

            if let showID = planToWatchID, showID.kind == .show {
                setShowDisposition(.active, for: showID, context: context, now: now)
            }
        }

        try context.save()
    }

    func setShowDisposition(_ disposition: ShowDisposition, for showID: MediaID) async throws {
        guard await resetGate.allowsLibraryWork() else {
            throw AppError.unknown("Wait for the library reset to finish before making changes.")
        }
        let context = persistence.makeContext()
        setShowDisposition(disposition, for: showID, context: context, now: Date())
        try context.save()
    }

    func showDisposition(for showID: MediaID) async -> ShowDisposition {
        let context = persistence.makeContext()
        return showDispositionRecord(for: showID, context: context)?.disposition ?? .active
    }

    // MARK: Library Queries

    func watchEvents(for id: MediaID) async -> [WatchHistoryItem] {
        let context = persistence.makeContext()
        return watchedEventRecords(for: id, context: context)
            .filter { !$0.tombstoned }
            .sorted { $0.watchedAt > $1.watchedAt }
            .map(makeHistoryItem(from:))
    }

    func watchHistory() async -> [WatchHistoryItem] {
        let context = persistence.makeContext()
        return allWatchedEventRecords(context: context)
            .filter { !$0.tombstoned }
            .sorted { $0.watchedAt > $1.watchedAt }
            .map(makeHistoryItem(from:))
    }

    private func makeHistoryItem(from event: WatchedEventRecord) -> WatchHistoryItem {
        WatchHistoryItem(
            id: event.recordID,
            mediaID: event.mediaID,
            showID: event.showTMDbID.map { showTMDbID in
                MediaID(kind: .show, id: showTMDbID, traktID: event.showTraktID)
            },
            seasonNumber: event.seasonNumber,
            episodeNumber: event.episodeNumber,
            watchedAt: event.watchedAt
        )
    }

    func removeWatchEvent(eventID: UUID) async throws {
        let deviceID = await deviceIdentityStore.currentDeviceID()
        guard await resetGate.allowsLibraryWork() else {
            throw AppError.unknown("Wait for the library reset to finish before making changes.")
        }
        let context = persistence.makeContext()
        guard let event = watchedEventRecord(forRecordID: eventID, context: context) else { return }

        let addKey = "history:add:\(event.eventKey)"
        let outstandingAdds = allSyncOperations(context: context).filter {
            $0.dedupeKey == addKey && $0.accountKey == (accountKeyProvider() ?? "")
        }
        let mayHaveReachedTrakt = outstandingAdds.contains {
            let payload = try? SyncPayloadCodec.decoder.decode(SyncOperationPayload.self, from: $0.payload)
            return $0.status != .pending || $0.attemptCount > 0 || payload?.historyRequestStartedAt != nil
                || payload?.originDeviceID != deviceID
        }
        if event.traktHistoryID != nil || mayHaveReachedTrakt {
            let historyID = event.traktHistoryID
            event.tombstoned = true
            event.dirty = true
            event.updatedAt = Date()

            let payload = SyncOperationPayload(
                mediaKind: event.mediaID.kind,
                tmdbID: event.tmdbID,
                traktID: event.traktID,
                showTMDbID: event.showTMDbID,
                showTraktID: event.showTraktID,
                seasonNumber: event.seasonNumber,
                episodeNumber: event.episodeNumber,
                watchedAt: event.watchedAt,
                historyID: historyID
            )
            try upsertSyncOperation(
                kind: .removeHistory,
                payload: payload,
                dedupeKey: "history:remove:\(event.eventKey)",
                context: context, accountKey: accountKeyProvider() ?? "", deviceID: deviceID
            )
        } else {
            removePendingAddHistory(for: event.eventKey, deviceID: deviceID, context: context)
            context.delete(event)
        }

        try context.save()
    }

    func latestWatchEventID(for id: MediaID) async -> UUID? {
        let context = persistence.makeContext()
        if id.kind == .episode, let episode = episodeRecord(forTMDbID: id.tmdbID, context: context) {
            return watchedEventRecords(forShowID: episode.showTMDbID, context: context)
                .filter { $0.seasonNumber == episode.seasonNumber && $0.episodeNumber == episode.episodeNumber && !$0.tombstoned }
                .sorted(by: { $0.watchedAt > $1.watchedAt })
                .first?
                .recordID
        }

        return watchedEventRecords(for: id, context: context)
            .filter { !$0.tombstoned }
            .sorted(by: { $0.watchedAt > $1.watchedAt })
            .first?
            .recordID
    }

    func isInWatchlist(_ id: MediaID) async -> Bool {
        let context = persistence.makeContext()
        return watchlistRecord(for: id, context: context)?.isInWatchlist == true
    }

    func isEpisodeWatched(_ ref: EpisodeRef) async -> Bool {
        let context = persistence.makeContext()
        return watchedEventRecords(forShowID: ref.showId, context: context)
            .contains {
                !$0.tombstoned &&
                $0.seasonNumber == ref.season &&
                $0.episodeNumber == ref.episode
            }
    }

    func previousUnwatchedEpisodes(before episode: EpisodeDetails) async -> [MediaID] {
        let showID = MediaID(kind: .show, id: episode.showId, traktID: episode.showTraktID)
        await enrichEpisodeCatalog(for: showID, throughSeason: episode.seasonNumber)

        guard let context = try? persistence.makeMetadataContext() else { return [] }
        let watchedKeys = Set(
            watchedEventRecords(forShowID: episode.showId, context: context)
                .filter { !$0.tombstoned }
                .compactMap { event -> String? in
                    guard let season = event.seasonNumber, let number = event.episodeNumber else { return nil }
                    return "ep:\(episode.showId):S\(season):E\(number)"
                }
        )

        return allEpisodeRecords(forShowID: episode.showId, context: context)
            .filter {
                $0.seasonNumber > 0
                    && ($0.seasonNumber, $0.episodeNumber) < (episode.seasonNumber, episode.episodeNumber)
                    && EpisodeAvailability.isReleased(airDate: $0.airDate, airedAt: $0.airedAt)
                    && !watchedKeys.contains($0.episodeKey)
            }
            .sorted {
                ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber)
            }
            .map { MediaID(kind: .episode, id: $0.tmdbID, traktID: $0.traktID) }
    }

    func movieLibraryItems() async throws -> [LibraryMovieItem] {
        try await snapshotReader.movieItems()
    }

    func libraryCounts() async throws -> LibraryCounts {
        try await snapshotReader.libraryCounts()
    }

    func releaseNotificationSnapshot(referenceDate: Date = .now) async throws -> ReleaseNotificationSnapshot {
        try await snapshotReader.releaseNotificationSnapshot(referenceDate: referenceDate)
    }

    func movieLibraryItems(revision: Int, forceRefresh: Bool = false) async throws -> [LibraryMovieItem] {
        if !forceRefresh, let cachedMovieSnapshot, cachedMovieSnapshot.revision == revision, Date().timeIntervalSince(cachedMovieSnapshot.cachedAt) < 60 {
            return cachedMovieSnapshot.items
        }
        let items = try await movieLibraryItems()
        cachedMovieSnapshot = (revision, .now, items)
        return items
    }

    func showLibraryItems() async throws -> [LibraryShowItem] {
        try await snapshotReader.showItems()
    }

    func showLibrarySnapshot(revision: Int, forceRefresh: Bool = false) async throws -> ShowLibrarySnapshot {
        if !forceRefresh, let cachedShowSnapshot, cachedShowSnapshot.revision == revision, Date().timeIntervalSince(cachedShowSnapshot.cachedAt) < 60 {
            return cachedShowSnapshot.snapshot
        }

        if forceRefresh {
            showSnapshotTask?.task.cancel()
            showSnapshotTask = nil
        }

        let pending: (revision: Int, token: UUID, task: Task<ShowLibrarySnapshot, Error>)
        if let existing = showSnapshotTask, existing.revision == revision {
            pending = existing
        } else {
            let snapshotReader = snapshotReader
            let task = Task {
                let items = try await snapshotReader.showItems()
                try Task.checkCancellation()
                return ShowLibrarySnapshot(items: items)
            }
            pending = (revision, UUID(), task)
            showSnapshotTask = pending
        }
        let task = pending.task
        let token = pending.token

        do {
            let snapshot = try await task.value
            try Task.checkCancellation()
            if showSnapshotTask?.token == token {
                cachedShowSnapshot = (revision, .now, snapshot)
                showSnapshotTask = nil
            }
            return snapshot
        } catch {
            if showSnapshotTask?.token == token {
                showSnapshotTask = nil
            }
            // Catalog writes or another refresh can supersede a shared read.
            // A caller that is still on screen should receive the replacement.
            if error.isCancelled, !Task.isCancelled {
                return try await showLibrarySnapshot(revision: revision)
            }
            throw error
        }
    }

    func showProgress(for showID: MediaID) async throws -> ShowProgress {
        let context = try persistence.makeMetadataContext()
        let episodeRows = allEpisodeRecords(forShowID: showID.tmdbID, context: context)
        let events = watchedEventRecords(forShowID: showID.tmdbID, context: context).filter { !$0.tombstoned }
        return makeShowProgress(
            for: showID,
            media: mediaRecord(for: showID, context: context),
            episodeRows: episodeRows,
            events: events
        )
    }

    private func makeShowProgress(for showID: MediaID,
                                  media: MediaRecord?,
                                  episodeRows: [EpisodeRecord],
                                  events: [WatchedEventRecord]) -> ShowProgress {
        let watchedKeys = Set(events.compactMap { event -> String? in
            guard let season = event.seasonNumber, let episode = event.episodeNumber else { return nil }
            return "ep:\(showID.tmdbID):S\(season):E\(episode)"
        })

        let trackableEpisodeRows: [EpisodeRecord] = {
            let regularEpisodes = episodeRows.filter { $0.seasonNumber > 0 }
            return regularEpisodes.isEmpty ? episodeRows : regularEpisodes
        }()
        let trackableKeys = Set(trackableEpisodeRows.map { "ep:\(showID.tmdbID):S\($0.seasonNumber):E\($0.episodeNumber)" })

        let trackedWatchedKeys = Set(events.compactMap { event -> String? in
            guard let season = event.seasonNumber, let episode = event.episodeNumber else { return nil }
            let key = "ep:\(showID.tmdbID):S\(season):E\(episode)"
            return trackableKeys.contains(key) ? key : nil
        })

        let released = trackableEpisodeRows.filter {
            EpisodeAvailability.isReleased(airDate: $0.airDate, airedAt: $0.airedAt)
        }

        let remaining = released.filter { row in
            !trackedWatchedKeys.contains("ep:\(showID.tmdbID):S\(row.seasonNumber):E\(row.episodeNumber)")
        }
        .sorted {
            ($0.airDate ?? .distantFuture) < ($1.airDate ?? .distantFuture)
        }

        let totalEpisodes = media?.totalEpisodes ?? trackableEpisodeRows.count.nonZero
        let next = remaining.first.map {
            ShowProgress.NextEpisode(
                tmdbID: $0.tmdbID,
                traktID: $0.traktID,
                season: $0.seasonNumber,
                episode: $0.episodeNumber,
                airDate: $0.airDate,
                airedAt: $0.airedAt,
                stillPath: $0.stillPath
            )
        }
        let nextUpcoming = trackableEpisodeRows
            .filter { !EpisodeAvailability.isReleased(airDate: $0.airDate, airedAt: $0.airedAt) }
            .filter {
                !trackedWatchedKeys.contains(
                    "ep:\(showID.tmdbID):S\($0.seasonNumber):E\($0.episodeNumber)"
                )
            }
            .sorted {
                ($0.airDate ?? .distantFuture) < ($1.airDate ?? .distantFuture)
            }
            .first
            .map {
                ShowProgress.NextEpisode(
                    tmdbID: $0.tmdbID,
                    traktID: $0.traktID,
                    season: $0.seasonNumber,
                    episode: $0.episodeNumber,
                    airDate: $0.airDate,
                    airedAt: $0.airedAt,
                    stillPath: $0.stillPath
                )
            }
        let mostRecentWatchedSeason = events
            .compactMap(\.seasonNumber)
            .filter { $0 > 0 }
            .max()

        return ShowProgress(
            watchedEpisodeKeys: watchedKeys,
            watchedCount: trackedWatchedKeys.count,
            totalEpisodes: totalEpisodes,
            remainingReleased: remaining.count,
            nextEpisode: next,
            nextUpcomingEpisode: nextUpcoming,
            mostRecentWatchedSeason: mostRecentWatchedSeason
        )
    }

    // MARK: Metadata Enrichment

    func enrichMetadata(for mediaID: MediaID) async throws {
        _ = try await mediaDetails(for: mediaID)
    }

    func enrichShowProgress(for showID: MediaID) async throws {
        _ = try await mediaDetails(for: showID)

        let context = try persistence.makeMetadataContext()
        guard let media = mediaRecord(for: showID, context: context),
              let seasons = decodeSeasons(media.seasonsData) else {
            return
        }

        let cachedEpisodeCounts = try await snapshotReader.episodeCounts(
            for: showID.tmdbID, seasons: seasons.map(\.seasonNumber)
        )

        for season in seasons
        where season.seasonNumber >= 0
            && (season.episodeCount.map {
                cachedEpisodeCounts[season.seasonNumber, default: 0] < $0
            } ?? true) {
            try Task.checkCancellation()
            _ = try await episodes(for: showID, seasonNumber: season.seasonNumber)
            await Task.yield()
        }
    }

    private func enrichEpisodeCatalog(for showID: MediaID, throughSeason targetSeason: Int) async {
        guard case let .show(show) = try? await mediaDetails(for: showID) else { return }

        guard let context = try? persistence.makeMetadataContext() else { return }
        let cachedEpisodeCounts = Dictionary(
            grouping: allEpisodeRecords(forShowID: showID.tmdbID, context: context),
            by: \.seasonNumber
        )
        .mapValues(\.count)

        for season in show.seasons
        where season.seasonNumber > 0
            && season.seasonNumber <= targetSeason
            && (season.episodeCount.map {
                cachedEpisodeCounts[season.seasonNumber, default: 0] < $0
            } ?? true) {
            guard !Task.isCancelled else { return }
            _ = try? await episodes(for: showID, seasonNumber: season.seasonNumber)
        }
    }

    func enrichUpcomingEpisodeAirtimes(for showID: MediaID) async -> Bool {
        guard let airtimeProvider, let showTraktID = showID.traktID else { return false }

        guard let context = try? persistence.makeMetadataContext() else { return false }
        let startOfToday = Calendar.current.startOfDay(for: .now)
        let candidates = allEpisodeRecords(forShowID: showID.tmdbID, context: context).filter {
            $0.airedAt == nil && ($0.airDate.map { $0 >= startOfToday } ?? false)
        }
        guard !candidates.isEmpty else { return false }

        var changed = false
        for seasonNumber in Set(candidates.map(\.seasonNumber)).sorted() {
            guard !Task.isCancelled else { return changed }
            guard let airtimes = try? await airtimeProvider.seasonAirtimes(
                showTraktID: showTraktID,
                seasonNumber: seasonNumber
            ) else { continue }

            let byEpisodeNumber = airtimes.reduce(into: [Int: EpisodeAirtime]()) {
                $0[$1.episodeNumber] = $1
            }
            for record in candidates where record.seasonNumber == seasonNumber {
                guard let airtime = byEpisodeNumber[record.episodeNumber] else { continue }
                record.traktID = airtime.traktID ?? record.traktID
                if record.airedAt != airtime.airedAt {
                    record.airedAt = airtime.airedAt
                    changed = true
                }
            }
        }

        if changed {
            try? context.save()
            cachedShowSnapshot = nil
            showSnapshotTask?.task.cancel()
            showSnapshotTask = nil
        }
        return changed
    }

    // MARK: Persistence Mapping

    private func cacheSearchItems(_ items: [SearchItem]) throws {
        let context = try persistence.makeMetadataContext()
        let now = Date()
        for item in items {
            let existing = mediaRecord(for: item.mediaID, context: context)
            if let existing {
                existing.traktID = existing.traktID ?? item.traktID
                existing.title = existing.title.isEmpty ? item.title : existing.title
                existing.posterPath = existing.posterPath ?? item.posterPath
                existing.updatedAt = now
            } else {
                let record = MediaRecord(
                    kind: item.kind,
                    tmdbID: item.id,
                    traktID: item.traktID,
                    title: item.title,
                    posterPath: item.posterPath,
                    updatedAt: now
                )
                context.insert(record)
            }
        }
        try context.save()
    }

    private func upsertMovie(_ movie: MovieDetails, requestedID: MediaID) throws {
        let context = try persistence.makeMetadataContext()
        let existing = mediaRecord(for: requestedID, context: context)
        if let existing {
            existing.traktID = requestedID.traktID ?? existing.traktID
            existing.title = movie.common.title
            existing.overview = movie.common.overview
            existing.tagline = movie.common.tagline
            existing.posterPath = movie.common.posterPath
            existing.backdropPath = movie.common.backdropPath
            existing.rating = movie.common.rating
            existing.ratingCount = movie.common.ratingCount
            existing.genres = movie.common.genres
            existing.releaseDate = movie.common.releaseDate
            existing.runtimeMinutes = movie.runtimeMinutes
            existing.updatedAt = .now
        } else {
            context.insert(
                MediaRecord(
                    kind: .movie,
                    tmdbID: movie.common.id,
                    traktID: requestedID.traktID ?? movie.common.traktID,
                    title: movie.common.title,
                    overview: movie.common.overview,
                    tagline: movie.common.tagline,
                    posterPath: movie.common.posterPath,
                    backdropPath: movie.common.backdropPath,
                    rating: movie.common.rating,
                    ratingCount: movie.common.ratingCount,
                    genres: movie.common.genres,
                    releaseDate: movie.common.releaseDate,
                    runtimeMinutes: movie.runtimeMinutes,
                    updatedAt: .now
                )
            )
        }
        try context.save()
    }

    private func upsertShow(_ show: ShowDetails, requestedID: MediaID) throws {
        let context = try persistence.makeMetadataContext()
        let seasonsData = try JSONEncoder().encode(show.seasons.map {
            StoredShowSeason(
                id: $0.id,
                traktID: $0.traktID,
                seasonNumber: $0.seasonNumber,
                name: $0.name,
                episodeCount: $0.episodeCount,
                posterPath: $0.posterPath
            )
        })

        let existing = mediaRecord(for: requestedID, context: context)
        if let existing {
            existing.traktID = requestedID.traktID ?? existing.traktID
            existing.title = show.common.title
            existing.overview = show.common.overview
            existing.tagline = show.common.tagline
            existing.posterPath = show.common.posterPath
            existing.backdropPath = show.common.backdropPath
            existing.rating = show.common.rating
            existing.ratingCount = show.common.ratingCount
            existing.genres = show.common.genres
            existing.releaseDate = show.common.releaseDate
            existing.totalEpisodes = show.totalEpisodes
            existing.nextAirDate = show.nextAirDate
            existing.statusRaw = show.status
            existing.seasonsData = seasonsData
            existing.updatedAt = .now
        } else {
            context.insert(
                MediaRecord(
                    kind: .show,
                    tmdbID: show.common.id,
                    traktID: requestedID.traktID ?? show.common.traktID,
                    title: show.common.title,
                    overview: show.common.overview,
                    tagline: show.common.tagline,
                    posterPath: show.common.posterPath,
                    backdropPath: show.common.backdropPath,
                    rating: show.common.rating,
                    ratingCount: show.common.ratingCount,
                    genres: show.common.genres,
                    releaseDate: show.common.releaseDate,
                    totalEpisodes: show.totalEpisodes,
                    nextAirDate: show.nextAirDate,
                    statusRaw: show.status,
                    seasonsData: seasonsData,
                    updatedAt: .now
                )
            )
        }
        try context.save()
    }

    private func upsertEpisodes(_ episodes: [EpisodeDetails], for showID: MediaID) throws {
        let context = try persistence.makeMetadataContext()
        let encoder = JSONEncoder()
        let seasonNumbers = Set(episodes.map(\.seasonNumber))
        var existingByKey = Dictionary(
            seasonNumbers.flatMap { episodeRecords(forShowID: showID.tmdbID, seasonNumber: $0, context: context) }.map {
                ("\($0.seasonNumber):\($0.episodeNumber)", $0)
            },
            uniquingKeysWith: { first, _ in first }
        )

        for episode in episodes {
            if let existing = existingByKey["\(episode.seasonNumber):\(episode.episodeNumber)"] {
                existing.traktID = episode.traktID ?? existing.traktID
                existing.showTraktID = showID.traktID ?? existing.showTraktID
                existing.name = episode.name
                existing.airDate = episode.airDate
                existing.airedAt = episode.airedAt ?? existing.airedAt
                existing.stillPath = episode.stillPath ?? existing.stillPath
                existing.overview = episode.overview ?? existing.overview
                existing.extrasData = try episode.extras.map { try encoder.encode($0) } ?? existing.extrasData
                existing.updatedAt = .now
            } else {
                let record = EpisodeRecord(
                    showTMDbID: showID.tmdbID,
                    showTraktID: showID.traktID,
                    tmdbID: episode.id,
                    traktID: episode.traktID,
                    seasonNumber: episode.seasonNumber,
                    episodeNumber: episode.episodeNumber,
                    name: episode.name,
                    airDate: episode.airDate,
                    airedAt: episode.airedAt,
                    stillPath: episode.stillPath,
                    overview: episode.overview,
                    extrasData: try episode.extras.map { try encoder.encode($0) },
                    updatedAt: .now
                )
                context.insert(record)
                existingByKey["\(episode.seasonNumber):\(episode.episodeNumber)"] = record
            }
        }

        try context.save()
        cachedShowSnapshot = nil
        showSnapshotTask?.task.cancel()
        showSnapshotTask = nil
    }

    private func upsertSyncOperation(kind: SyncOperationKind,
                                     payload: SyncOperationPayload,
                                     dedupeKey: String,
                                     context: ModelContext, accountKey: String, deviceID: String) throws {
        var payload = payload
        payload.originDeviceID = deviceID
        payload.mutationAt = Date()
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)
        if let existing = syncOperation(forDedupeKey: dedupeKey, accountKey: accountKey, deviceID: deviceID, context: context), existing.status == .pending {
            existing.kindRaw = kind.rawValue
            existing.payload = try SyncPayloadCodec.encoder.encode(payload)
            existing.status = .pending
            existing.claimedAt = nil
            existing.claimedByDeviceID = nil
            existing.generationID = generationID
            existing.createdAt = payload.mutationAt ?? Date()
            existing.nextAttemptAt = nil
            existing.attemptCount = 0
            return
        }

        let operation = SyncOperationRecord(
            kind: kind,
            payload: try SyncPayloadCodec.encoder.encode(payload),
            dedupeKey: dedupeKey,
            accountKey: accountKey,
            generationID: generationID
        )
        context.insert(operation)
    }

    private func removePendingAddHistory(for eventKey: String, deviceID: String, context: ModelContext) {
        let key = "history:add:\(eventKey)"
        if let existing = syncOperation(forDedupeKey: key, accountKey: accountKeyProvider() ?? "", deviceID: deviceID, context: context), existing.status == .pending {
            context.delete(existing)
        }
    }

    private func merged(_ details: MovieDetails, requestedID: MediaID) -> MovieDetails {
        let common = MediaCommon(
            id: details.common.id,
            traktID: requestedID.traktID ?? details.common.traktID,
            title: details.common.title,
            overview: details.common.overview,
            tagline: details.common.tagline,
            posterPath: details.common.posterPath,
            backdropPath: details.common.backdropPath,
            rating: details.common.rating,
            ratingCount: details.common.ratingCount,
            genres: details.common.genres,
            releaseDate: details.common.releaseDate
        )
        return MovieDetails(common: common, runtimeMinutes: details.runtimeMinutes)
    }

    private func merged(_ details: ShowDetails, requestedID: MediaID) -> ShowDetails {
        let common = MediaCommon(
            id: details.common.id,
            traktID: requestedID.traktID ?? details.common.traktID,
            title: details.common.title,
            overview: details.common.overview,
            tagline: details.common.tagline,
            posterPath: details.common.posterPath,
            backdropPath: details.common.backdropPath,
            rating: details.common.rating,
            ratingCount: details.common.ratingCount,
            genres: details.common.genres,
            releaseDate: details.common.releaseDate
        )
        return ShowDetails(
            common: common,
            seasons: details.seasons,
            totalEpisodes: details.totalEpisodes,
            nextAirDate: details.nextAirDate,
            status: details.status
        )
    }

    private func isMediaRecordComplete(_ record: MediaRecord) -> Bool {
        guard !record.title.isEmpty, record.posterPath != nil else { return false }

        switch record.kind {
        case .movie:
            // Search results only cache title/poster. Do not present that partial
            // record as a full movie detail, or the detail sheet has only its header.
            return record.overview?.isEmpty == false
                || record.backdropPath != nil
                || record.runtimeMinutes != nil
        case .show:
            return record.overview?.isEmpty == false && record.seasonsData != nil
        default:
            return false
        }
    }

    private func mapMediaRecord(_ record: MediaRecord) throws -> MediaDetails {
        let common = MediaCommon(
            id: record.tmdbID,
            traktID: record.traktID,
            title: record.title,
            overview: record.overview,
            tagline: record.tagline,
            posterPath: record.posterPath,
            backdropPath: record.backdropPath,
            rating: record.rating,
            ratingCount: record.ratingCount,
            genres: record.genres,
            releaseDate: record.releaseDate
        )

        switch record.kind {
        case .movie:
            return .movie(MovieDetails(common: common, runtimeMinutes: record.runtimeMinutes))
        case .show:
            let seasons = decodeSeasons(record.seasonsData)?.map {
                ShowDetails.Season(
                    id: $0.id,
                    traktID: $0.traktID,
                    seasonNumber: $0.seasonNumber,
                    name: $0.name,
                    episodeCount: $0.episodeCount,
                    posterPath: $0.posterPath
                )
            } ?? []
            return .show(
                ShowDetails(
                    common: common,
                    seasons: seasons,
                    totalEpisodes: record.totalEpisodes,
                    nextAirDate: record.nextAirDate,
                    status: record.statusRaw
                )
            )
        default:
            throw AppError.featureNotImplemented("Only movie and show detail mapping is supported.")
        }
    }

    private func mapEpisodeRecord(_ record: EpisodeRecord) -> EpisodeDetails {
        let decoder = JSONDecoder()
        let extras = record.extrasData.flatMap { try? decoder.decode(EpisodeDetails.Extras.self, from: $0) }
        return EpisodeDetails(
            id: record.tmdbID,
            traktID: record.traktID,
            showId: record.showTMDbID,
            showTraktID: record.showTraktID,
            seasonNumber: record.seasonNumber,
            episodeNumber: record.episodeNumber,
            name: record.name,
            airDate: record.airDate,
            airedAt: record.airedAt,
            stillPath: record.stillPath,
            overview: record.overview,
            extras: extras
        )
    }

    private func mapShowStatus(_ record: MediaRecord?) -> ShowStatusSnapshot {
        let status = (record?.statusRaw ?? "").lowercased().replacingOccurrences(of: " ", with: "")
        let nextAirDate = record?.nextAirDate

        let bucket: ShowStatusSnapshot.Bucket = {
            if status.contains("ended") || status.contains("canceled") || status.contains("cancelled") {
                return .ended
            }
            if let nextAirDate,
               Calendar.current.startOfDay(for: nextAirDate) >= Calendar.current.startOfDay(for: Date()) {
                return .airing
            }
            return .returning
        }()

        return ShowStatusSnapshot(bucket: bucket, nextAirDate: nextAirDate)
    }

    private func decodeSeasons(_ data: Data?) -> [StoredShowSeason]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([StoredShowSeason].self, from: data)
    }

    // MARK: Record Queries

    private func mediaRecord(for id: MediaID, context: ModelContext) -> MediaRecord? {
        let mediaKey = id.stableKey
        var descriptor = FetchDescriptor<MediaRecord>(
            predicate: #Predicate { $0.mediaKey == mediaKey }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func episodeRecord(for ref: EpisodeRef, context: ModelContext) -> EpisodeRecord? {
        let showID = ref.showId
        let seasonNumber = ref.season
        let episodeNumber = ref.episode
        var descriptor = FetchDescriptor<EpisodeRecord>(
            predicate: #Predicate {
                $0.showTMDbID == showID &&
                    $0.seasonNumber == seasonNumber &&
                    $0.episodeNumber == episodeNumber
            }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func episodeRecord(forTMDbID tmdbID: Int, context: ModelContext) -> EpisodeRecord? {
        var descriptor = FetchDescriptor<EpisodeRecord>(
            predicate: #Predicate { $0.tmdbID == tmdbID }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func watchlistRecord(for id: MediaID, context: ModelContext) -> WatchlistRecord? {
        let mediaKey = id.stableKey
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)
        let descriptor = FetchDescriptor<WatchlistRecord>(
            predicate: #Predicate { $0.mediaKey == mediaKey }
        )
        return (try? context.fetch(descriptor))?.first {
            LibraryGenerationPolicy.belongsToCurrentGeneration($0.generationID, current: generationID)
        }
    }

    private func showDispositionRecord(for id: MediaID, context: ModelContext) -> ShowDispositionRecord? {
        let mediaKey = id.stableKey
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)
        let descriptor = FetchDescriptor<ShowDispositionRecord>(
            predicate: #Predicate { $0.mediaKey == mediaKey }
        )
        return (try? context.fetch(descriptor))?.first {
            LibraryGenerationPolicy.belongsToCurrentGeneration($0.generationID, current: generationID)
        }
    }

    private func setShowDisposition(
        _ disposition: ShowDisposition,
        for showID: MediaID,
        context: ModelContext,
        now: Date
    ) {
        let record = showDispositionRecord(for: showID, context: context)
            ?? ShowDispositionRecord(
                showID: showID,
                disposition: disposition,
                updatedAt: now,
                generationID: LibraryGenerationPolicy.currentGeneration(in: context)
            )
        if record.modelContext == nil { context.insert(record) }
        record.traktID = showID.traktID ?? record.traktID
        record.disposition = disposition
        record.updatedAt = now
    }

    private func watchedEventRecord(forRecordID recordID: UUID, context: ModelContext) -> WatchedEventRecord? {
        allWatchedEventRecords(context: context).first { $0.recordID == recordID }
    }

    private func watchedEventRecord(forEventKey key: String, context: ModelContext) -> WatchedEventRecord? {
        allWatchedEventRecords(context: context).first { $0.eventKey == key }
    }

    private func syncOperation(forDedupeKey key: String, accountKey: String, deviceID: String, context: ModelContext) -> SyncOperationRecord? {
        allSyncOperations(context: context).first {
            $0.dedupeKey == key && $0.accountKey == accountKey && $0.status == .pending
                && (try? SyncPayloadCodec.decoder.decode(SyncOperationPayload.self, from: $0.payload).originDeviceID) == deviceID
        }
    }

    private func allMediaRecords(context: ModelContext) -> [MediaRecord] {
        (try? context.fetch(FetchDescriptor<MediaRecord>())) ?? []
    }

    private func allEpisodeRecords(context: ModelContext) -> [EpisodeRecord] {
        (try? context.fetch(FetchDescriptor<EpisodeRecord>())) ?? []
    }

    private func allEpisodeRecords(forShowID showID: Int, context: ModelContext) -> [EpisodeRecord] {
        (try? context.fetch(FetchDescriptor<EpisodeRecord>(
            predicate: #Predicate { $0.showTMDbID == showID },
            sortBy: [
                SortDescriptor(\.seasonNumber),
                SortDescriptor(\.episodeNumber)
            ]
        ))) ?? []
    }

    private func episodeRecords(forShowID showID: Int, seasonNumber: Int, context: ModelContext) -> [EpisodeRecord] {
        (try? context.fetch(FetchDescriptor<EpisodeRecord>(
            predicate: #Predicate {
                $0.showTMDbID == showID && $0.seasonNumber == seasonNumber
            },
            sortBy: [SortDescriptor(\.episodeNumber)]
        ))) ?? []
    }

    private func allWatchlistRecords(context: ModelContext) -> [WatchlistRecord] {
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)
        return ((try? context.fetch(FetchDescriptor<WatchlistRecord>())) ?? [])
            .filter { LibraryGenerationPolicy.belongsToCurrentGeneration($0.generationID, current: generationID) }
    }

    private func allWatchedEventRecords(context: ModelContext) -> [WatchedEventRecord] {
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)
        return ((try? context.fetch(FetchDescriptor<WatchedEventRecord>())) ?? [])
            .filter { LibraryGenerationPolicy.belongsToCurrentGeneration($0.generationID, current: generationID) }
    }

    private func allShowDispositionRecords(context: ModelContext) -> [ShowDispositionRecord] {
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)
        return ((try? context.fetch(FetchDescriptor<ShowDispositionRecord>())) ?? [])
            .filter { LibraryGenerationPolicy.belongsToCurrentGeneration($0.generationID, current: generationID) }
    }

    private func watchedEventRecords(for id: MediaID, context: ModelContext) -> [WatchedEventRecord] {
        let tmdbID = id.tmdbID
        let kindRaw = id.kind.rawValue
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)
        return ((try? context.fetch(FetchDescriptor<WatchedEventRecord>(
            predicate: #Predicate { $0.tmdbID == tmdbID && $0.kindRaw == kindRaw }
        ))) ?? [])
        .filter { LibraryGenerationPolicy.belongsToCurrentGeneration($0.generationID, current: generationID) }
    }

    private func watchedEventRecords(forShowID showID: Int, context: ModelContext) -> [WatchedEventRecord] {
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)
        return ((try? context.fetch(FetchDescriptor<WatchedEventRecord>(
            predicate: #Predicate { $0.showTMDbID == showID }
        ))) ?? [])
        .filter { LibraryGenerationPolicy.belongsToCurrentGeneration($0.generationID, current: generationID) }
    }

    private func allSyncOperations(context: ModelContext) -> [SyncOperationRecord] {
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)
        return ((try? context.fetch(FetchDescriptor<SyncOperationRecord>())) ?? [])
            .filter { LibraryGenerationPolicy.belongsToCurrentGeneration($0.generationID, current: generationID) }
    }
}

// MARK: - Cache Policies

nonisolated enum EpisodeSeasonCachePolicy {
    static func shouldRefresh(
        cachedCount: Int,
        expectedEpisodeCount: Int?,
        hasMissingArtwork: Bool,
        attemptedArtworkRefresh: Bool
    ) -> Bool {
        guard cachedCount > 0 else { return true }
        if let expectedEpisodeCount, cachedCount < expectedEpisodeCount {
            return true
        }
        return hasMissingArtwork && !attemptedArtworkRefresh
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
