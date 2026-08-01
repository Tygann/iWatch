import Foundation
import SwiftData

actor LibrarySnapshotReader {
    private let persistence: Persistence

    init(persistence: Persistence) {
        self.persistence = persistence
    }

    func movieItems() throws -> [LibraryMovieItem] {
        let context = persistence.makeContext()
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)
        let includesLegacyRows = generationID == LibraryGenerationPolicy.legacyGenerationID
        let movieKind = MediaKind.movie.rawValue
        let watchlist = try context.fetch(FetchDescriptor<WatchlistRecord>(
            predicate: #Predicate {
                ($0.generationID == generationID || (includesLegacyRows && $0.generationID == "")) &&
                    $0.kindRaw == movieKind && $0.isInWatchlist
            },
            sortBy: [SortDescriptor(\.localUpdatedAt, order: .reverse)]
        ))
        let events = try context.fetch(FetchDescriptor<WatchedEventRecord>(
            predicate: #Predicate {
                ($0.generationID == generationID || (includesLegacyRows && $0.generationID == "")) &&
                    $0.kindRaw == movieKind && !$0.tombstoned
            }
        ))
        let media = try context.fetch(FetchDescriptor<MediaRecord>(
            predicate: #Predicate { $0.kindRaw == movieKind }
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
                isWatched: event != nil,
                lastWatchedAt: event?.watchedAt
            )
        }
    }

    func showItems() throws -> [LibraryShowItem] {
        let context = persistence.makeContext()
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)
        let includesLegacyRows = generationID == LibraryGenerationPolicy.legacyGenerationID
        let showKind = MediaKind.show.rawValue
        let watchlist = try context.fetch(FetchDescriptor<WatchlistRecord>(
            predicate: #Predicate {
                ($0.generationID == generationID || (includesLegacyRows && $0.generationID == "")) &&
                    $0.kindRaw == showKind && $0.isInWatchlist
            },
            sortBy: [SortDescriptor(\.localUpdatedAt, order: .reverse)]
        ))
        let media = try context.fetch(FetchDescriptor<MediaRecord>(
            predicate: #Predicate { $0.kindRaw == showKind }
        ))
        let mediaByID = Dictionary(
            media.map { ($0.tmdbID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let episodesByShowID = Dictionary(
            grouping: try context.fetch(FetchDescriptor<EpisodeRecord>()),
            by: \.showTMDbID
        )
        let eventsByShowID = Dictionary(
            grouping: try context.fetch(FetchDescriptor<WatchedEventRecord>(
                predicate: #Predicate {
                    ($0.generationID == generationID || (includesLegacyRows && $0.generationID == "")) &&
                        !$0.tombstoned
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
        let today = Calendar.current.startOfDay(for: Date())
        let remaining = trackableEpisodes
            .filter { episode in
                guard let airDate = episode.airDate else { return false }
                let key = "ep:\(showID.tmdbID):S\(episode.seasonNumber):E\(episode.episodeNumber)"
                return Calendar.current.startOfDay(for: airDate) <= today && !watchedTrackableKeys.contains(key)
            }
            .sorted { ($0.airDate ?? .distantFuture) < ($1.airDate ?? .distantFuture) }
        let next = remaining.first.map {
            ShowProgress.NextEpisode(
                tmdbID: $0.tmdbID,
                traktID: $0.traktID,
                season: $0.seasonNumber,
                episode: $0.episodeNumber,
                airDate: $0.airDate
            )
        }
        let episodeCount = trackableEpisodes.count

        return ShowProgress(
            watchedEpisodeKeys: watchedKeys,
            watchedCount: watchedTrackableKeys.count,
            totalEpisodes: media?.totalEpisodes ?? (episodeCount == 0 ? nil : episodeCount),
            remainingReleased: remaining.count,
            nextEpisode: next
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
