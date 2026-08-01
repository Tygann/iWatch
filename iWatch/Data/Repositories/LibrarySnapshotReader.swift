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
        let watchedIDs = Set(events.map(\.tmdbID))

        return watchlist.map { row in
            let media = mediaByKey["\(movieKind):\(row.tmdbID)"]
            return LibraryMovieItem(
                mediaID: row.mediaID,
                title: media?.title ?? "Unknown",
                posterPath: media?.posterPath,
                releaseDate: media?.releaseDate,
                isWatched: watchedIDs.contains(row.tmdbID)
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

        return watchlist.map { row in
            let media = mediaByID[row.tmdbID]
            return LibraryShowItem(
                mediaID: row.mediaID,
                title: media?.title ?? "Unknown",
                posterPath: media?.posterPath,
                status: showStatus(from: media),
                progress: showProgress(
                    for: row.mediaID,
                    media: media,
                    episodes: episodesByShowID[row.tmdbID] ?? [],
                    events: eventsByShowID[row.tmdbID] ?? []
                ),
                needsProgressEnrichment: needsProgressEnrichment(
                    media: media,
                    episodes: episodesByShowID[row.tmdbID] ?? []
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

    private func showStatus(from record: MediaRecord?) -> ShowStatusSnapshot {
        let status = (record?.statusRaw ?? "").lowercased().replacingOccurrences(of: " ", with: "")
        let nextAirDate = record?.nextAirDate
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
