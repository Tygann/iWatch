import Foundation
import SwiftData

// MARK: - Library Snapshot Reader

actor LibrarySnapshotReader {
    private let persistence: Persistence

    init(persistence: Persistence) {
        self.persistence = persistence
    }

    func expireProviderMetadata() throws -> Bool {
        try persistence.expireProviderMetadata(in: persistence.makeContext())
    }

    func readMetadata<Value: Sendable>(
        _ read: @Sendable (ModelContext) throws -> Value
    ) throws -> Value {
        try Task.checkCancellation()
        return try read(persistence.makeContext())
    }

    func episodeCounts(for showID: Int, seasons: [Int]) throws -> [Int: Int] {
        let context = persistence.makeContext()
        let now = Date()
        let cutoff = Persistence.metadataCutoff(at: now)
        var counts: [Int: Int] = [:]
        for season in seasons {
            try Task.checkCancellation()
            counts[season] = try context.fetchCount(FetchDescriptor<EpisodeRecord>(
                predicate: #Predicate { $0.showTMDbID == showID && $0.seasonNumber == season && $0.metadataCachedAt > cutoff && $0.metadataCachedAt <= now }
            ))
        }
        return counts
    }

    func libraryCounts() async throws -> LibraryCounts {
        let movies = try movieItems()
        let shows = try showItems()
        let context = persistence.makeContext()
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)
        let includesLegacyRows = generationID == LibraryGenerationPolicy.legacyGenerationID
        let plays = try context.fetchCount(FetchDescriptor<WatchedEventRecord>(
            predicate: #Predicate {
                ($0.generationID == generationID || (includesLegacyRows && $0.generationID == "")) && !$0.tombstoned
            }
        ))
        return await MainActor.run {
            let snapshot = ShowLibrarySnapshot(items: shows)
            return LibraryCounts(watchlistMovies: movies.filter(\.isInWatchlist).count,
                watchlistShows: snapshot.watchlist.count, watchedPlays: plays,
                showsInProgress: snapshot.continueWatching.count)
        }
    }

    // MARK: Release Notifications

    func releaseNotificationSnapshot(referenceDate: Date = .now) throws -> ReleaseNotificationSnapshot {
        let context = persistence.makeContext()
        let now = Date()
        let cutoff = Persistence.metadataCutoff(at: now)
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)
        let includesLegacyRows = generationID == LibraryGenerationPolicy.legacyGenerationID
        let watchlist = try activeWatchlist(context.fetch(FetchDescriptor<WatchlistRecord>(
            predicate: #Predicate {
                $0.generationID == generationID || (includesLegacyRows && $0.generationID == "")
            }
        )))
        guard !watchlist.isEmpty else { return .init(movies: [], episodes: []) }

        let showKind = MediaKind.show.rawValue
        let movieKind = MediaKind.movie.rawValue
        let showIDs = watchlist.filter { $0.kindRaw == showKind }.map(\.tmdbID)
        let movieIDs = watchlist.filter { $0.kindRaw == movieKind }.map(\.tmdbID)
        let media = try context.fetch(FetchDescriptor<MediaRecord>(predicate: #Predicate {
            $0.metadataCachedAt > cutoff && $0.metadataCachedAt <= now &&
                (($0.kindRaw == movieKind && movieIDs.contains($0.tmdbID)) ||
                 ($0.kindRaw == showKind && showIDs.contains($0.tmdbID)))
        }))
        let dispositions = try context.fetch(FetchDescriptor<ShowDispositionRecord>(
            predicate: #Predicate {
                ($0.generationID == generationID || (includesLegacyRows && $0.generationID == "")) &&
                    showIDs.contains($0.tmdbID)
            }
        ))
        let stoppedShowIDs = Set(dispositions.filter { $0.disposition == .stopped }.map(\.tmdbID))
        let activeShowIDs = showIDs.filter { !stoppedShowIDs.contains($0) }
        let episodes = try context.fetch(FetchDescriptor<EpisodeRecord>(predicate: #Predicate {
            activeShowIDs.contains($0.showTMDbID) && $0.seasonNumber > 0 && $0.airDate != nil &&
                $0.metadataCachedAt > cutoff && $0.metadataCachedAt <= now
        }))
        let events: [WatchedEventRecord]
        if episodes.isEmpty {
            events = []
        } else {
            events = try context.fetch(FetchDescriptor<WatchedEventRecord>(
                predicate: #Predicate {
                    ($0.generationID == generationID || (includesLegacyRows && $0.generationID == "")) &&
                        !$0.tombstoned && $0.showTMDbID != nil
                }
            ))
        }
        let mediaByKey = Dictionary(
            media.map { ("\($0.kindRaw):\($0.tmdbID)", $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let activeShows = Set(activeShowIDs)
        let watchedEpisodeKeys = Set(events.compactMap { event -> String? in
            guard let showID = event.showTMDbID, activeShows.contains(showID),
                  let season = event.seasonNumber,
                  let episode = event.episodeNumber else { return nil }
            return "ep:\(showID):S\(season):E\(episode)"
        })

        let movies = watchlist.compactMap { row -> ReleaseNotificationSnapshot.MovieRelease? in
            guard row.kindRaw == MediaKind.movie.rawValue,
                  let record = mediaByKey["\(row.kindRaw):\(row.tmdbID)"],
                  let releaseDate = record.releaseDate,
                  Calendar.current.startOfDay(for: releaseDate) >= Calendar.current.startOfDay(for: referenceDate)
            else { return nil }
            return .init(mediaID: row.mediaID, title: record.title, releaseDate: releaseDate)
        }

        let showMediaByID = Dictionary(
            media.filter { $0.kind == .show }.map { ($0.tmdbID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let episodeReleases = episodes.compactMap { episode -> ReleaseNotificationSnapshot.EpisodeRelease? in
            guard !watchedEpisodeKeys.contains(episode.episodeKey),
                  let airDate = episode.airDate,
                  Calendar.current.startOfDay(for: airDate) >= Calendar.current.startOfDay(for: referenceDate),
                  let show = showMediaByID[episode.showTMDbID]
            else { return nil }

            return .init(
                showID: MediaID(kind: .show, id: episode.showTMDbID, traktID: episode.showTraktID ?? show.traktID),
                episode: EpisodeRef(
                    showId: episode.showTMDbID,
                    showTraktID: episode.showTraktID ?? show.traktID,
                    season: episode.seasonNumber,
                    episode: episode.episodeNumber,
                    tmdbID: episode.tmdbID,
                    traktID: episode.traktID
                ),
                showTitle: show.title,
                episodeTitle: episode.name,
                airDate: airDate,
                airedAt: episode.airedAt
            )
        }

        return ReleaseNotificationSnapshot(movies: movies, episodes: episodeReleases)
    }

    private func activeWatchlist(_ records: [WatchlistRecord]) -> [WatchlistRecord] {
        let rows = Dictionary(records.map { ("\($0.kindRaw):\($0.tmdbID)", $0) }) { current, candidate in
            WatchlistRecord.prefersMembership(candidate, over: current) ? candidate : current
        }
        return rows.values.filter(\.isInWatchlist).sorted {
            if $0.localUpdatedAt != $1.localUpdatedAt { return $0.localUpdatedAt > $1.localUpdatedAt }
            return $0.tmdbID < $1.tmdbID
        }
    }

    // MARK: Movies

    func movieItems() throws -> [LibraryMovieItem] {
        let context = persistence.makeContext()
        let now = Date()
        let cutoff = Persistence.metadataCutoff(at: now)
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)
        let includesLegacyRows = generationID == LibraryGenerationPolicy.legacyGenerationID
        let movieKind = MediaKind.movie.rawValue
        let watchlist = try activeWatchlist(context.fetch(FetchDescriptor<WatchlistRecord>(
            predicate: #Predicate {
                ($0.generationID == generationID || (includesLegacyRows && $0.generationID == "")) &&
                    $0.kindRaw == movieKind
            }
        )))
        let events = try context.fetch(FetchDescriptor<WatchedEventRecord>(
            predicate: #Predicate {
                ($0.generationID == generationID || (includesLegacyRows && $0.generationID == "")) &&
                    $0.kindRaw == movieKind && !$0.tombstoned
            }
        ))
        let media = try context.fetch(FetchDescriptor<MediaRecord>(
            predicate: #Predicate { $0.kindRaw == movieKind && $0.metadataCachedAt > cutoff && $0.metadataCachedAt <= now }
        ))
        let mediaByKey = Dictionary(
            media.map { ("\($0.kindRaw):\($0.tmdbID)", $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let watchlistByID = Dictionary(
            watchlist.map { ($0.tmdbID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let latestEventByID = Dictionary(
            grouping: events,
            by: \.tmdbID
        ).mapValues { events in
            events.max { $0.watchedAt < $1.watchedAt }!
        }
        let playCountByID = Dictionary(grouping: events, by: \.tmdbID).mapValues(\.count)
        let historyOnlyIDs = latestEventByID.keys
            .filter { watchlistByID[$0] == nil }
            .sorted {
                (latestEventByID[$0]?.watchedAt ?? .distantPast) >
                    (latestEventByID[$1]?.watchedAt ?? .distantPast)
            }
        let movieIDs = watchlist.map(\.tmdbID) + historyOnlyIDs

        return movieIDs.compactMap { tmdbID in
            let row = watchlistByID[tmdbID]
            let event = latestEventByID[tmdbID]
            guard let mediaID = row?.mediaID ?? event?.mediaID else { return nil }
            let media = mediaByKey["\(movieKind):\(tmdbID)"]
            return LibraryMovieItem(
                mediaID: mediaID,
                title: media?.title ?? "Unknown",
                posterPath: media?.posterPath,
                releaseDate: media?.releaseDate,
                listedAt: row.flatMap { $0.listedAt ?? $0.localUpdatedAt },
                isInWatchlist: row != nil,
                playCount: playCountByID[tmdbID, default: 0],
                lastWatchedAt: event?.watchedAt
            )
        }
    }

    // MARK: Shows

    func showItems(for showID: Int? = nil) throws -> [LibraryShowItem] {
        let context = persistence.makeContext()
        let now = Date()
        let cutoff = Persistence.metadataCutoff(at: now)
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)
        let includesLegacyRows = generationID == LibraryGenerationPolicy.legacyGenerationID
        let showKind = MediaKind.show.rawValue
        let requestedID = showID ?? 0
        let includesAllShows = showID == nil
        let watchlist = try activeWatchlist(context.fetch(FetchDescriptor<WatchlistRecord>(
            predicate: #Predicate {
                ($0.generationID == generationID || (includesLegacyRows && $0.generationID == "")) &&
                    $0.kindRaw == showKind &&
                    (includesAllShows || $0.tmdbID == requestedID)
            }
        )))
        let media = try context.fetch(FetchDescriptor<MediaRecord>(
            predicate: #Predicate { $0.kindRaw == showKind && (includesAllShows || $0.tmdbID == requestedID) && $0.metadataCachedAt > cutoff && $0.metadataCachedAt <= now }
        ))
        let dispositions = try context.fetch(FetchDescriptor<ShowDispositionRecord>(
            predicate: #Predicate {
                $0.generationID == generationID || (includesLegacyRows && $0.generationID == "")
            }
        ))
        let dispositionByID = Dictionary(
            dispositions.map { ($0.tmdbID, $0.disposition) },
            uniquingKeysWith: { first, _ in first }
        )
        let mediaByID = Dictionary(
            media.map { ($0.tmdbID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let episodesByShowID = Dictionary(
            grouping: try context.fetch(FetchDescriptor<EpisodeRecord>(
                predicate: #Predicate { (includesAllShows || $0.showTMDbID == requestedID) && $0.metadataCachedAt > cutoff && $0.metadataCachedAt <= now }
            )),
            by: \.showTMDbID
        )
        let eventsByShowID = Dictionary(
            grouping: try context.fetch(FetchDescriptor<WatchedEventRecord>(
                predicate: #Predicate {
                    ($0.generationID == generationID || (includesLegacyRows && $0.generationID == "")) &&
                        !$0.tombstoned && $0.showTMDbID != nil && (includesAllShows || $0.showTMDbID == requestedID)
                }
            ))
        ) { $0.showTMDbID ?? -1 }
        let watchlistByID = Dictionary(
            watchlist.map { ($0.tmdbID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let historyOnlyIDs = eventsByShowID.keys
            .filter { $0 >= 0 && watchlistByID[$0] == nil }
            .sorted {
                (eventsByShowID[$0]?.map(\.watchedAt).max() ?? .distantPast) >
                    (eventsByShowID[$1]?.map(\.watchedAt).max() ?? .distantPast)
            }
        let showIDs = watchlist.map(\.tmdbID) + historyOnlyIDs

        return showIDs.map { tmdbID in
            let row = watchlistByID[tmdbID]
            let history = eventsByShowID[tmdbID] ?? []
            let media = mediaByID[tmdbID]
            let episodes = episodesByShowID[tmdbID] ?? []
            let mediaID = row?.mediaID ?? MediaID(
                kind: .show,
                id: tmdbID,
                traktID: media?.traktID ?? history.compactMap(\.showTraktID).first
            )
            return LibraryShowItem(
                mediaID: mediaID,
                title: media?.title ?? "Unknown",
                posterPath: media?.posterPath,
                status: showStatus(from: media, episodes: episodes),
                progress: showProgress(
                    for: mediaID,
                    media: media,
                    episodes: episodes,
                    events: history
                ),
                isInWatchlist: row != nil,
                disposition: dispositionByID[tmdbID] ?? .active,
                listedAt: row.flatMap { $0.listedAt ?? $0.localUpdatedAt },
                lastWatchedAt: history.map(\.watchedAt).max(),
                needsProgressEnrichment: needsProgressEnrichment(
                    media: media,
                    episodes: episodes
                )
            )
        }
    }

    private func needsProgressEnrichment(
        media: MediaRecord?,
        episodes: [EpisodeRecord]
    ) -> Bool {
        guard let seasonsData = media?.seasonsData,
              let seasons = try? JSONDecoder().decode([StoredShowSeason].self, from: seasonsData) else {
            return true
        }

        let cachedCounts = Dictionary(grouping: episodes, by: \.seasonNumber).mapValues(\.count)
        return LibraryProgressEnrichmentPolicy.needsEnrichment(
            seasons: seasons,
            cachedEpisodeCounts: cachedCounts
        )
    }

    private func showProgress(
        for showID: MediaID,
        media: MediaRecord?,
        episodes: [EpisodeRecord],
        events: [WatchedEventRecord]
    ) -> ShowProgress {
        let watchedKeys = Set(events.compactMap { event -> String? in
            guard let season = event.seasonNumber, let episode = event.episodeNumber else { return nil }
            return "ep:\(showID.tmdbID):S\(season):E\(episode)"
        })
        let regularEpisodes = episodes.filter { $0.seasonNumber > 0 }
        let trackableEpisodes = regularEpisodes.isEmpty ? episodes : regularEpisodes
        let trackableKeys = Set(trackableEpisodes.map {
            "ep:\(showID.tmdbID):S\($0.seasonNumber):E\($0.episodeNumber)"
        })
        let watchedTrackableKeys = watchedKeys.intersection(trackableKeys)
        let released = trackableEpisodes.filter {
            EpisodeAvailability.isReleased(airDate: $0.airDate, airedAt: $0.airedAt)
        }
        let remaining = released
            .filter { episode in
                let key = "ep:\(showID.tmdbID):S\(episode.seasonNumber):E\(episode.episodeNumber)"
                return !watchedTrackableKeys.contains(key)
            }
        let next = remaining.min {
            ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber)
        }.map {
            ShowProgress.NextEpisode(
                tmdbID: $0.tmdbID,
                traktID: $0.traktID,
                season: $0.seasonNumber,
                episode: $0.episodeNumber,
                airDate: $0.airDate,
                airedAt: $0.airedAt,
                stillPath: $0.stillPath,
                name: $0.name
            )
        }
        let nextUpcoming = trackableEpisodes
            .filter { !EpisodeAvailability.isReleased(airDate: $0.airDate, airedAt: $0.airedAt) }
            .filter { episode in
                !watchedTrackableKeys.contains(
                    "ep:\(showID.tmdbID):S\(episode.seasonNumber):E\(episode.episodeNumber)"
                )
            }
            .sorted { ($0.airDate ?? .distantFuture) < ($1.airDate ?? .distantFuture) }
            .first
            .map {
                ShowProgress.NextEpisode(
                    tmdbID: $0.tmdbID,
                    traktID: $0.traktID,
                    season: $0.seasonNumber,
                    episode: $0.episodeNumber,
                    airDate: $0.airDate,
                    airedAt: $0.airedAt,
                    stillPath: $0.stillPath,
                    name: $0.name
                )
            }
        let mostRecentWatchedSeason = events
            .compactMap(\.seasonNumber)
            .filter { $0 > 0 }
            .max()
        let episodeCount = trackableEpisodes.count

        return ShowProgress(
            watchedEpisodeKeys: watchedKeys,
            watchedCount: watchedTrackableKeys.count,
            totalEpisodes: media?.totalEpisodes ?? (episodeCount == 0 ? nil : episodeCount),
            remainingReleased: remaining.count,
            nextEpisode: next,
            nextUpcomingEpisode: nextUpcoming,
            mostRecentWatchedSeason: mostRecentWatchedSeason,
            watchedReleasedCount: released.count - remaining.count
        )
    }

    private func showStatus(from record: MediaRecord?, episodes: [EpisodeRecord]) -> ShowStatusSnapshot {
        let status = (record?.statusRaw ?? "").lowercased().replacingOccurrences(of: " ", with: "")
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let nextAirDate = ([record?.nextAirDate] + episodes.map(\.airDate))
            .compactMap { $0 }
            .filter { Calendar.current.startOfDay(for: $0) >= startOfToday }
            .min()
        let bucket: ShowStatusSnapshot.Bucket
        if status.contains("ended") || status.contains("canceled") || status.contains("cancelled") {
            bucket = .ended
        } else if let nextAirDate,
                  Calendar.current.startOfDay(for: nextAirDate) >= Calendar.current.startOfDay(for: Date()) {
            bucket = .airing
        } else {
            bucket = .returning
        }
        return ShowStatusSnapshot(bucket: bucket, nextAirDate: nextAirDate)
    }
}

// MARK: - Progress Enrichment Policy

nonisolated enum LibraryProgressEnrichmentPolicy {
    static func needsEnrichment(
        seasons: [StoredShowSeason],
        cachedEpisodeCounts: [Int: Int]
    ) -> Bool {
        seasons.contains { season in
            guard season.seasonNumber >= 0 else { return false }
            let cachedCount = cachedEpisodeCounts[season.seasonNumber, default: 0]
            if let expectedCount = season.episodeCount {
                return cachedCount < expectedCount
            }
            return cachedCount == 0
        }
    }
}
