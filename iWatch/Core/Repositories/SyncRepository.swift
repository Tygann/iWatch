import Foundation
import SwiftData

enum SyncReason: String, Sendable {
    case appLaunch
    case foreground
    case userInitiated
    case background
}

actor SyncEngine {
    struct Snapshot: Sendable {
        let initialBaselineComplete: Bool
        let hasPendingOperations: Bool
        let hasProcessingOperations: Bool
        let deadletterOperationCount: Int
        let lastSuccessfulPullAt: Date?
        let lastSuccessfulPushAt: Date?
        let lastSeenRemoteActivityAt: Date?
    }

    private let persistence: Persistence
    private let trakt: any TraktSyncing
    private let deviceIdentityStore: DeviceIdentityStore

    private let suspiciousWatchlistRemovalThreshold = 25
    private let completedOperationRetention: TimeInterval = 24 * 60 * 60
    private let deadletterRetention: TimeInterval = 30 * 24 * 60 * 60

    private static let claimCoordinator = SyncClaimCoordinator()

    private var lastRunErrorDescription: String?

    init(persistence: Persistence, trakt: any TraktSyncing, deviceIdentityStore: DeviceIdentityStore) {
        self.persistence = persistence
        self.trakt = trakt
        self.deviceIdentityStore = deviceIdentityStore
    }

    func ensureInitialBaseline() async throws {
        let token = await trakt.currentToken()
        guard token != nil else { return }

        let context = persistence.makeContext()
        let state = syncState(context: context)
        guard !state.initialBaselineComplete else { return }

        try await pullAndMerge(into: context, state: state, initialBaseline: true)
        state.initialBaselineComplete = true
        try context.save()
    }

    @discardableResult
    func run(reason: SyncReason) async -> Bool {
        do {
            lastRunErrorDescription = nil

            let repairContext = persistence.makeContext()
            _ = try performIntegrityRepair(context: repairContext, now: Date())
            try repairContext.save()

            try await ensureInitialBaseline()

            let pullContext = persistence.makeContext()
            let state = syncState(context: pullContext)
            try await pullAndMerge(into: pullContext, state: state, initialBaseline: false)
            try pullContext.save()

            try await pushPendingOperations()
            return true
        } catch {
            lastRunErrorDescription = descriptiveError(error)
            #if DEBUG
            print("[SyncEngine] \(reason.rawValue) failed:", error)
            #endif
            return false
        }
    }

    func snapshot() -> Snapshot {
        let context = persistence.makeContext()
        let operations = allOperations(context: context)
        let state = syncState(context: context)

        return Snapshot(
            initialBaselineComplete: state.initialBaselineComplete,
            hasPendingOperations: operations.contains { $0.status == .pending },
            hasProcessingOperations: operations.contains { $0.status == .processing },
            deadletterOperationCount: operations.filter { $0.status == .deadletter }.count,
            lastSuccessfulPullAt: state.lastSuccessfulPullAt,
            lastSuccessfulPushAt: state.lastSuccessfulPushAt,
            lastSeenRemoteActivityAt: state.lastSeenRemoteActivityAt
        )
    }

    func diagnostics() -> SyncDiagnostics {
        let context = persistence.makeContext()
        let operations = allOperations(context: context)
        let state = syncState(context: context)

        return SyncDiagnostics(
            initialBaselineComplete: state.initialBaselineComplete,
            pendingOperationCount: operations.filter { $0.status == .pending }.count,
            processingOperationCount: operations.filter { $0.status == .processing }.count,
            deadletterOperationCount: operations.filter { $0.status == .deadletter }.count,
            duplicateCandidateCount: duplicateCandidateCount(context: context),
            lastSuccessfulPullAt: state.lastSuccessfulPullAt,
            lastSuccessfulPushAt: state.lastSuccessfulPushAt,
            lastSeenRemoteActivityAt: state.lastSeenRemoteActivityAt,
            lastErrorDescription: lastRunErrorDescription
        )
    }

    func hasPendingOperations() -> Bool {
        let snapshot = snapshot()
        return snapshot.hasPendingOperations || snapshot.hasProcessingOperations
    }

    func shouldRefreshOnForeground(maxStaleness: TimeInterval) -> Bool {
        let snapshot = snapshot()
        if snapshot.hasPendingOperations || snapshot.hasProcessingOperations {
            return true
        }

        let lastSuccessfulSyncAt = [snapshot.lastSuccessfulPullAt, snapshot.lastSuccessfulPushAt]
            .compactMap { $0 }
            .max()

        guard let lastSuccessfulSyncAt else {
            return true
        }

        return Date().timeIntervalSince(lastSuccessfulSyncAt) >= maxStaleness
    }

    func enqueue(_ operation: SyncOperationPayload) async throws {
        let context = persistence.makeContext()
        let kind: SyncOperationKind
        switch operation.historyID {
        case .some:
            kind = .removeHistory
        case .none where operation.watchedAt != nil:
            kind = .addHistory
        default:
            kind = .addWatchlist
        }
        let data = try SyncPayloadCodec.encoder.encode(operation)
        context.insert(SyncOperationRecord(kind: kind, payload: data))
        try context.save()
    }

    @discardableResult
    func retryDeadletterOperations() throws -> Int {
        let context = persistence.makeContext()
        let deadletters = allOperations(context: context).filter { $0.status == .deadletter }

        for operation in deadletters {
            operation.status = .pending
            operation.attemptCount = 0
            operation.lastAttemptAt = nil
            operation.claimedByDeviceID = nil
            operation.claimedAt = nil
        }

        if !deadletters.isEmpty {
            try context.save()
        }

        return deadletters.count
    }

    @discardableResult
    func repairIntegrity() throws -> SyncIntegrityRepairSummary {
        let context = persistence.makeContext()
        let summary = try performIntegrityRepair(context: context, now: Date())
        if summary.totalChanges > 0 {
            try context.save()
        }
        return summary
    }

    func resetLocalTraktSyncCache() throws {
        let context = persistence.makeContext()

        for operation in allOperations(context: context) {
            context.delete(operation)
        }
        for row in allWatchlist(context: context) {
            context.delete(row)
        }
        for event in allEvents(context: context) {
            context.delete(event)
        }
        for state in allSyncStates(context: context) {
            context.delete(state)
        }

        lastRunErrorDescription = nil
        try context.save()
    }

    func assignUnlinkedOperations(to accountKey: String) throws {
        let context = persistence.makeContext()
        for operation in allOperations(context: context) where operation.accountKey.isEmpty {
            operation.accountKey = accountKey
        }
        try context.save()
    }

    func eraseAllAppData() throws {
        let context = persistence.makeContext()

        for media in allMedia(context: context) {
            context.delete(media)
        }
        for episode in allEpisodes(context: context) {
            context.delete(episode)
        }
        for operation in allOperations(context: context) {
            context.delete(operation)
        }
        for row in allWatchlist(context: context) {
            context.delete(row)
        }
        for event in allEvents(context: context) {
            context.delete(event)
        }
        for state in allSyncStates(context: context) {
            context.delete(state)
        }

        lastRunErrorDescription = nil
        try context.save()
    }

    private func pullAndMerge(into context: ModelContext,
                              state: SyncStateRecord,
                              initialBaseline: Bool) async throws {
        let previousRelevantActivityAt = state.lastSeenRemoteActivityAt
        let remoteActivities = try? await trakt.getLastActivities()
        let shouldPullWatchlist = initialBaseline || shouldPullWatchlist(remoteActivities, previousRelevantActivityAt: previousRelevantActivityAt)
        let shouldPullHistory = initialBaseline
            || state.lastSuccessfulPullAt == nil
            || shouldPullHistory(remoteActivities, previousRelevantActivityAt: previousRelevantActivityAt)

        let remoteWatchlist = shouldPullWatchlist ? try await trakt.getWatchlist() : []
        let remoteHistory = shouldPullHistory ? try await trakt.getHistory(startAt: initialBaseline ? nil : state.lastSuccessfulPullAt) : []
        let now = Date()

        if shouldPullWatchlist {
            try mergeWatchlist(
                remoteWatchlist,
                context: context,
                now: now,
                allowRemoteRemoval: !initialBaseline,
                remoteUpdatedAt: remoteActivities?.watchlistActivityAt
            )
        }

        if shouldPullHistory {
            try mergeHistory(remoteHistory, context: context, now: now)
        }

        state.lastSuccessfulPullAt = now
        state.lastSeenRemoteActivityAt = newest([
            state.lastSeenRemoteActivityAt,
            remoteActivities?.relevantActivityAt
        ])
    }

    private func shouldPullWatchlist(_ remoteActivities: TraktLastActivitiesDTO?,
                                     previousRelevantActivityAt: Date?) -> Bool {
        guard let remoteActivities else { return true }
        guard let previousRelevantActivityAt else { return true }
        guard let watchlistActivityAt = remoteActivities.watchlistActivityAt else { return true }
        return watchlistActivityAt > previousRelevantActivityAt
    }

    private func shouldPullHistory(_ remoteActivities: TraktLastActivitiesDTO?,
                                   previousRelevantActivityAt: Date?) -> Bool {
        guard let remoteActivities else { return true }
        guard let previousRelevantActivityAt else { return true }
        guard let historyActivityAt = remoteActivities.historyActivityAt else { return true }
        return historyActivityAt > previousRelevantActivityAt
    }

    private func pushPendingOperations() async throws {
        guard let accountKey = TraktLinkStore.activeAccountKey else { return }
        let deviceID = await deviceIdentityStore.currentDeviceID()
        let now = Date()
        while let operationID = try await claimNextOperation(deviceID: deviceID, accountKey: accountKey) {
            let processContext = persistence.makeContext()
            guard let operation = operationRecord(id: operationID, context: processContext),
                  operation.claimedByDeviceID == deviceID,
                  operation.status == .processing else {
                continue
            }

            do {
                try await process(operation: operation, context: processContext)
                operation.status = .succeeded
                operation.claimedByDeviceID = nil
                operation.claimedAt = nil
                try processContext.save()
            } catch {
                operation.attemptCount += 1
                let attemptedAt = Date()
                operation.lastAttemptAt = attemptedAt
                operation.claimedByDeviceID = nil
                operation.claimedAt = nil
                if isRetryable(error), operation.attemptCount < 5 {
                    operation.status = .pending
                    operation.nextAttemptAt = attemptedAt.addingTimeInterval(retryDelay(forAttempt: operation.attemptCount))
                } else {
                    operation.status = .deadletter
                    operation.nextAttemptAt = nil
                }
                try processContext.save()
                throw error
            }
        }

        let cleanupContext = persistence.makeContext()
        _ = pruneCompletedOperations(context: cleanupContext, now: now)
        try cleanupContext.save()

        let stateContext = persistence.makeContext()
        let state = syncState(context: stateContext)
        state.lastSuccessfulPushAt = Date()
        try stateContext.save()
    }

    private func claimNextOperation(deviceID: String, accountKey: String) async throws -> UUID? {
        try await Self.claimCoordinator.claimNextOperation(
            in: persistence,
            deviceID: deviceID,
            accountKey: accountKey,
            claimExpiration: 300
        )
    }

    private func isRetryable(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return urlError.code != .cancelled && urlError.code != .unsupportedURL
        }
        if case let .httpStatus(code, _) = error as? AppError {
            return code == 408 || code == 425 || code == 429 || (500...599).contains(code)
        }
        return true
    }

    private func retryDelay(forAttempt attempt: Int) -> TimeInterval {
        min(pow(2, Double(max(attempt - 1, 0))) * 30, 30 * 60)
    }

    private func process(operation: SyncOperationRecord, context: ModelContext) async throws {
        let payload = try SyncPayloadCodec.decoder.decode(SyncOperationPayload.self, from: operation.payload)

        switch operation.kind {
        case .addWatchlist:
            if let mediaID = payload.mediaKind.flatMap({ kind in payload.tmdbID.map { MediaID(kind: kind, id: $0, traktID: payload.traktID) } }) {
                try await trakt.addToWatchlist([mediaID])
                if let row = watchlistRecord(for: mediaID, context: context) {
                    row.dirty = false
                    row.isInWatchlist = true
                    row.remoteUpdatedAt = Date()
                }
            }
        case .removeWatchlist:
            if let mediaID = payload.mediaKind.flatMap({ kind in payload.tmdbID.map { MediaID(kind: kind, id: $0, traktID: payload.traktID) } }) {
                try await trakt.removeFromWatchlist([mediaID])
                if let row = watchlistRecord(for: mediaID, context: context) {
                    row.dirty = false
                    row.isInWatchlist = false
                    row.remoteUpdatedAt = Date()
                }
            }
        case .addHistory:
            try await trakt.addToHistory([payload])
            if let event = payload.mediaKind.flatMap({ kind in payload.tmdbID.flatMap { eventRecord(kind: kind, tmdbID: $0, watchedAt: payload.watchedAt, context: context) } }) {
                event.dirty = false
                event.updatedAt = Date()
            }
        case .removeHistory:
            if let historyID = payload.historyID {
                try await trakt.removeFromHistory(historyIDs: [historyID])
                if let event = eventRecord(historyID: historyID, context: context) {
                    context.delete(event)
                }
            }
        }

        try context.save()
    }

    private func mergeWatchlist(_ remoteItems: [TraktWatchlistItemDTO],
                                context: ModelContext,
                                now: Date,
                                allowRemoteRemoval: Bool,
                                remoteUpdatedAt: Date?) throws {
        var remoteKeys = Set<String>()

        for item in remoteItems {
            switch item.type {
            case .movie:
                guard let movie = item.movie, let tmdbID = movie.ids.tmdb else { continue }
                let mediaID = MediaID(kind: .movie, id: tmdbID, traktID: movie.ids.trakt)
                remoteKeys.insert(mediaID.stableKey)
                upsertMediaFromWatchlist(mediaID: mediaID, title: movie.title ?? "Unknown", year: movie.year, context: context)
                let row = watchlistRecord(for: mediaID, context: context) ?? WatchlistRecord(mediaID: mediaID, isInWatchlist: true)
                if row.modelContext == nil { context.insert(row) }
                if !row.dirty {
                    row.traktID = mediaID.traktID ?? row.traktID
                    row.isInWatchlist = true
                    row.listedAt = item.listedAt
                    row.remoteUpdatedAt = item.listedAt ?? remoteUpdatedAt ?? now
                    row.localUpdatedAt = max(row.localUpdatedAt, now)
                }
            case .show:
                guard let show = item.show, let tmdbID = show.ids.tmdb else { continue }
                let mediaID = MediaID(kind: .show, id: tmdbID, traktID: show.ids.trakt)
                remoteKeys.insert(mediaID.stableKey)
                upsertMediaFromWatchlist(mediaID: mediaID, title: show.title ?? "Unknown", year: show.year, context: context)
                let row = watchlistRecord(for: mediaID, context: context) ?? WatchlistRecord(mediaID: mediaID, isInWatchlist: true)
                if row.modelContext == nil { context.insert(row) }
                if !row.dirty {
                    row.traktID = mediaID.traktID ?? row.traktID
                    row.isInWatchlist = true
                    row.listedAt = item.listedAt
                    row.remoteUpdatedAt = item.listedAt ?? remoteUpdatedAt ?? now
                    row.localUpdatedAt = max(row.localUpdatedAt, now)
                }
            default:
                continue
            }
        }

        guard allowRemoteRemoval else { return }

        let missingRows = allWatchlist(context: context)
            .filter { $0.isInWatchlist && !$0.dirty && !remoteKeys.contains($0.mediaKey) }

        guard !missingRows.isEmpty else { return }

        if remoteItems.isEmpty && missingRows.count >= suspiciousWatchlistRemovalThreshold {
            lastRunErrorDescription = "Skipped \(missingRows.count) remote watchlist removals because the watchlist payload looked suspicious."
            return
        }

        for row in missingRows {
            row.isInWatchlist = false
            row.dirty = false
            row.remoteUpdatedAt = remoteUpdatedAt ?? now
            row.localUpdatedAt = max(row.localUpdatedAt, now)
        }
    }

    private func mergeHistory(_ remoteItems: [TraktHistoryItemDTO],
                              context: ModelContext,
                              now: Date) throws {
        for item in remoteItems {
            guard let watchedAt = item.watchedAt else { continue }

            switch item.type {
            case .movie:
                guard let movie = item.movie, let tmdbID = movie.ids.tmdb else { continue }
                let existing = eventRecord(kind: .movie, tmdbID: tmdbID, watchedAt: watchedAt, context: context)
                    ?? eventRecord(historyID: item.id, context: context)
                let event = existing ?? WatchedEventRecord(
                    kind: .movie,
                    tmdbID: tmdbID,
                    traktID: movie.ids.trakt,
                    watchedAt: watchedAt,
                    traktHistoryID: item.id,
                    dirty: false,
                    tombstoned: false,
                    createdAt: now,
                    updatedAt: now
                )
                if existing == nil { context.insert(event) }
                if event.tombstoned && event.dirty {
                    continue
                }
                event.eventKey = WatchedEventRecord.makeEventKey(kind: .movie, tmdbID: tmdbID, traktID: movie.ids.trakt, watchedAt: watchedAt)
                event.traktID = movie.ids.trakt ?? event.traktID
                event.traktHistoryID = item.id
                event.dirty = false
                event.tombstoned = false
                event.updatedAt = now
                upsertMediaFromWatchlist(
                    mediaID: MediaID(kind: .movie, id: tmdbID, traktID: movie.ids.trakt),
                    title: movie.title ?? "Unknown",
                    year: movie.year,
                    context: context
                )
            case .episode:
                guard let episode = item.episode, let tmdbID = episode.ids.tmdb else { continue }
                let showTMDbID = item.show?.ids.tmdb
                let existing = eventRecord(kind: .episode, tmdbID: tmdbID, watchedAt: watchedAt, context: context)
                    ?? eventRecord(historyID: item.id, context: context)
                let event = existing ?? WatchedEventRecord(
                    kind: .episode,
                    tmdbID: tmdbID,
                    traktID: episode.ids.trakt,
                    showTMDbID: showTMDbID,
                    showTraktID: item.show?.ids.trakt,
                    seasonNumber: episode.season,
                    episodeNumber: episode.number,
                    watchedAt: watchedAt,
                    traktHistoryID: item.id,
                    dirty: false,
                    tombstoned: false,
                    createdAt: now,
                    updatedAt: now
                )
                if existing == nil { context.insert(event) }
                if event.tombstoned && event.dirty {
                    continue
                }
                event.eventKey = WatchedEventRecord.makeEventKey(kind: .episode, tmdbID: tmdbID, traktID: episode.ids.trakt, watchedAt: watchedAt)
                event.traktID = episode.ids.trakt ?? event.traktID
                event.showTMDbID = showTMDbID ?? event.showTMDbID
                event.showTraktID = item.show?.ids.trakt ?? event.showTraktID
                event.seasonNumber = episode.season ?? event.seasonNumber
                event.episodeNumber = episode.number ?? event.episodeNumber
                event.traktHistoryID = item.id
                event.dirty = false
                event.tombstoned = false
                event.updatedAt = now

                if let showTMDbID {
                    upsertMediaFromWatchlist(
                        mediaID: MediaID(kind: .show, id: showTMDbID, traktID: item.show?.ids.trakt),
                        title: item.show?.title ?? "Unknown",
                        year: item.show?.year,
                        context: context
                    )
                    upsertEpisodeFromHistory(showTMDbID: showTMDbID, showTraktID: item.show?.ids.trakt, episode: episode, context: context)
                }
            default:
                continue
            }
        }
    }

    private func performIntegrityRepair(context: ModelContext, now: Date) throws -> SyncIntegrityRepairSummary {
        let mediaMerged = repairMediaDuplicates(context: context)
        let episodesMerged = repairEpisodeDuplicates(context: context)
        let watchlistMerged = repairWatchlistDuplicates(context: context)
        let watchedEventsMerged = repairWatchedEventDuplicates(context: context)
        let operationsMerged = repairSyncOperationDuplicates(context: context, now: now)
        let syncStatesMerged = repairSyncStateDuplicates(context: context)
        let prunedCompletedOperations = pruneCompletedOperations(context: context, now: now)

        return SyncIntegrityRepairSummary(
            mediaMerged: mediaMerged,
            episodesMerged: episodesMerged,
            watchlistMerged: watchlistMerged,
            watchedEventsMerged: watchedEventsMerged,
            operationsMerged: operationsMerged,
            syncStatesMerged: syncStatesMerged,
            prunedCompletedOperations: prunedCompletedOperations
        )
    }

    private func repairMediaDuplicates(context: ModelContext) -> Int {
        let groups = Dictionary(grouping: allMedia(context: context)) {
            $0.mediaKey.isEmpty ? "\($0.kindRaw):\($0.tmdbID)" : $0.mediaKey
        }
        var merged = 0

        for group in groups.values where group.count > 1 {
            let ordered = group.sorted { mediaPreferredOver($0, $1) }
            guard let canonical = ordered.first else { continue }
            canonical.mediaKey = canonical.mediaKey.isEmpty ? "\(canonical.kind.rawValue):\(canonical.tmdbID)" : canonical.mediaKey

            for duplicate in ordered.dropFirst() {
                mergeMedia(canonical, with: duplicate)
                context.delete(duplicate)
                merged += 1
            }
        }

        return merged
    }

    private func repairEpisodeDuplicates(context: ModelContext) -> Int {
        let groups = Dictionary(grouping: allEpisodes(context: context)) {
            $0.episodeKey.isEmpty ? "ep:\($0.showTMDbID):S\($0.seasonNumber):E\($0.episodeNumber)" : $0.episodeKey
        }
        var merged = 0

        for group in groups.values where group.count > 1 {
            let ordered = group.sorted { episodePreferredOver($0, $1) }
            guard let canonical = ordered.first else { continue }
            canonical.episodeKey = canonical.episodeKey.isEmpty ? "ep:\(canonical.showTMDbID):S\(canonical.seasonNumber):E\(canonical.episodeNumber)" : canonical.episodeKey

            for duplicate in ordered.dropFirst() {
                mergeEpisode(canonical, with: duplicate)
                context.delete(duplicate)
                merged += 1
            }
        }

        return merged
    }

    private func repairWatchlistDuplicates(context: ModelContext) -> Int {
        let groups = Dictionary(grouping: allWatchlist(context: context)) {
            $0.mediaKey.isEmpty ? "\($0.kindRaw):\($0.tmdbID)" : $0.mediaKey
        }
        var merged = 0

        for group in groups.values where group.count > 1 {
            let ordered = group.sorted { watchlistPreferredOver($0, $1) }
            guard let canonical = ordered.first else { continue }
            canonical.mediaKey = canonical.mediaKey.isEmpty ? "\(canonical.mediaID.kind.rawValue):\(canonical.tmdbID)" : canonical.mediaKey

            for duplicate in ordered.dropFirst() {
                mergeWatchlist(canonical, with: duplicate)
                context.delete(duplicate)
                merged += 1
            }
        }

        return merged
    }

    private func repairWatchedEventDuplicates(context: ModelContext) -> Int {
        let groups = Dictionary(grouping: allEvents(context: context)) { event in
            eventDeduplicationKey(event)
        }
        var merged = 0

        for group in groups.values where group.count > 1 {
            let ordered = group.sorted { watchedEventPreferredOver($0, $1) }
            guard let canonical = ordered.first else { continue }
            canonical.eventKey = WatchedEventRecord.makeEventKey(
                kind: canonical.mediaID.kind,
                tmdbID: canonical.tmdbID,
                traktID: canonical.traktID,
                watchedAt: canonical.watchedAt
            )

            for duplicate in ordered.dropFirst() {
                mergeWatchedEvent(canonical, with: duplicate)
                context.delete(duplicate)
                merged += 1
            }
        }

        return merged
    }

    private func repairSyncOperationDuplicates(context: ModelContext, now: Date) -> Int {
        let groups = Dictionary(grouping: allOperations(context: context).filter { !($0.dedupeKey?.isEmpty ?? true) }) {
            $0.dedupeKey ?? UUID().uuidString
        }
        var merged = 0

        for group in groups.values where group.count > 1 {
            let ordered = group.sorted { syncOperationPreferredOver($0, $1) }
            guard let canonical = ordered.first else { continue }

            for duplicate in ordered.dropFirst() {
                mergeSyncOperation(canonical, with: duplicate, now: now)
                context.delete(duplicate)
                merged += 1
            }
        }

        for operation in allOperations(context: context) where operation.status == .processing && isClaimExpired(operation, now: now) {
            operation.status = .pending
            operation.claimedByDeviceID = nil
            operation.claimedAt = nil
        }

        return merged
    }

    private func repairSyncStateDuplicates(context: ModelContext) -> Int {
        let groups = Dictionary(grouping: allSyncStates(context: context)) {
            $0.accountKey.isEmpty ? "default" : $0.accountKey
        }
        var merged = 0

        for group in groups.values where group.count > 1 {
            let ordered = group.sorted { syncStatePreferredOver($0, $1) }
            guard let canonical = ordered.first else { continue }
            canonical.accountKey = canonical.accountKey.isEmpty ? "default" : canonical.accountKey

            for duplicate in ordered.dropFirst() {
                mergeSyncState(canonical, with: duplicate)
                context.delete(duplicate)
                merged += 1
            }
        }

        return merged
    }

    private func pruneCompletedOperations(context: ModelContext, now: Date) -> Int {
        let operations = allOperations(context: context)
        var pruned = 0

        for operation in operations {
            switch operation.status {
            case .succeeded where now.timeIntervalSince(operation.createdAt) > completedOperationRetention:
                context.delete(operation)
                pruned += 1
            case .deadletter where now.timeIntervalSince(operation.createdAt) > deadletterRetention:
                context.delete(operation)
                pruned += 1
            default:
                continue
            }
        }

        return pruned
    }

    private func duplicateCandidateCount(context: ModelContext) -> Int {
        duplicateOverflowCount(for: allMedia(context: context).map { $0.mediaKey.isEmpty ? "\($0.kindRaw):\($0.tmdbID)" : $0.mediaKey })
        + duplicateOverflowCount(for: allEpisodes(context: context).map { $0.episodeKey.isEmpty ? "ep:\($0.showTMDbID):S\($0.seasonNumber):E\($0.episodeNumber)" : $0.episodeKey })
        + duplicateOverflowCount(for: allWatchlist(context: context).map { $0.mediaKey.isEmpty ? "\($0.kindRaw):\($0.tmdbID)" : $0.mediaKey })
        + duplicateOverflowCount(for: allEvents(context: context).map { eventDeduplicationKey($0) })
        + duplicateOverflowCount(for: allOperations(context: context).compactMap(\.dedupeKey))
        + duplicateOverflowCount(for: allSyncStates(context: context).map { $0.accountKey.isEmpty ? "default" : $0.accountKey })
    }

    private func duplicateOverflowCount(for keys: [String]) -> Int {
        Dictionary(grouping: keys, by: { $0 })
            .values
            .reduce(0) { partialResult, group in
                partialResult + max(group.count - 1, 0)
            }
    }

    private func mediaPreferredOver(_ lhs: MediaRecord, _ rhs: MediaRecord) -> Bool {
        let lhsScore = mediaCompletenessScore(lhs)
        let rhsScore = mediaCompletenessScore(rhs)
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func mediaCompletenessScore(_ record: MediaRecord) -> Int {
        var score = 0
        if !record.title.isEmpty { score += 1 }
        if record.overview?.isEmpty == false { score += 1 }
        if record.posterPath != nil { score += 1 }
        if record.backdropPath != nil { score += 1 }
        if record.traktID != nil { score += 1 }
        if record.seasonsData != nil { score += 1 }
        if !record.genres.isEmpty { score += 1 }
        return score
    }

    private func mergeMedia(_ canonical: MediaRecord, with duplicate: MediaRecord) {
        canonical.mediaKey = canonical.mediaKey.isEmpty ? duplicate.mediaKey : canonical.mediaKey
        canonical.kindRaw = canonical.kindRaw.isEmpty ? duplicate.kindRaw : canonical.kindRaw
        if canonical.tmdbID == 0 { canonical.tmdbID = duplicate.tmdbID }
        canonical.traktID = canonical.traktID ?? duplicate.traktID
        if canonical.title.isEmpty { canonical.title = duplicate.title }
        canonical.overview = canonical.overview ?? duplicate.overview
        canonical.tagline = canonical.tagline ?? duplicate.tagline
        canonical.posterPath = canonical.posterPath ?? duplicate.posterPath
        canonical.backdropPath = canonical.backdropPath ?? duplicate.backdropPath
        canonical.rating = canonical.rating ?? duplicate.rating
        canonical.ratingCount = canonical.ratingCount ?? duplicate.ratingCount
        if canonical.genres.isEmpty { canonical.genres = duplicate.genres }
        canonical.releaseDate = newest([canonical.releaseDate, duplicate.releaseDate])
        canonical.runtimeMinutes = canonical.runtimeMinutes ?? duplicate.runtimeMinutes
        canonical.totalEpisodes = canonical.totalEpisodes ?? duplicate.totalEpisodes
        canonical.nextAirDate = newest([canonical.nextAirDate, duplicate.nextAirDate])
        canonical.statusRaw = canonical.statusRaw ?? duplicate.statusRaw
        canonical.seasonsData = canonical.seasonsData ?? duplicate.seasonsData
        canonical.updatedAt = max(canonical.updatedAt, duplicate.updatedAt)
    }

    private func episodePreferredOver(_ lhs: EpisodeRecord, _ rhs: EpisodeRecord) -> Bool {
        let lhsScore = episodeCompletenessScore(lhs)
        let rhsScore = episodeCompletenessScore(rhs)
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func episodeCompletenessScore(_ record: EpisodeRecord) -> Int {
        var score = 0
        if record.traktID != nil { score += 1 }
        if !record.name.isEmpty { score += 1 }
        if record.airDate != nil { score += 1 }
        if record.stillPath != nil { score += 1 }
        if record.overview?.isEmpty == false { score += 1 }
        if record.extrasData != nil { score += 1 }
        return score
    }

    private func mergeEpisode(_ canonical: EpisodeRecord, with duplicate: EpisodeRecord) {
        canonical.episodeKey = canonical.episodeKey.isEmpty ? duplicate.episodeKey : canonical.episodeKey
        if canonical.showTMDbID == 0 { canonical.showTMDbID = duplicate.showTMDbID }
        canonical.showTraktID = canonical.showTraktID ?? duplicate.showTraktID
        if canonical.tmdbID == 0 { canonical.tmdbID = duplicate.tmdbID }
        canonical.traktID = canonical.traktID ?? duplicate.traktID
        if canonical.seasonNumber == 0 { canonical.seasonNumber = duplicate.seasonNumber }
        if canonical.episodeNumber == 0 { canonical.episodeNumber = duplicate.episodeNumber }
        if canonical.name.isEmpty { canonical.name = duplicate.name }
        canonical.airDate = newest([canonical.airDate, duplicate.airDate])
        canonical.stillPath = canonical.stillPath ?? duplicate.stillPath
        canonical.overview = canonical.overview ?? duplicate.overview
        canonical.extrasData = canonical.extrasData ?? duplicate.extrasData
        canonical.updatedAt = max(canonical.updatedAt, duplicate.updatedAt)
    }

    private func watchlistPreferredOver(_ lhs: WatchlistRecord, _ rhs: WatchlistRecord) -> Bool {
        if lhs.dirty != rhs.dirty { return lhs.dirty && !rhs.dirty }
        let lhsDate = newest([lhs.localUpdatedAt, lhs.remoteUpdatedAt]) ?? .distantPast
        let rhsDate = newest([rhs.localUpdatedAt, rhs.remoteUpdatedAt]) ?? .distantPast
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        if lhs.isInWatchlist != rhs.isInWatchlist { return lhs.isInWatchlist && !rhs.isInWatchlist }
        return lhs.traktID != nil && rhs.traktID == nil
    }

    private func mergeWatchlist(_ canonical: WatchlistRecord, with duplicate: WatchlistRecord) {
        canonical.mediaKey = canonical.mediaKey.isEmpty ? duplicate.mediaKey : canonical.mediaKey
        canonical.kindRaw = canonical.kindRaw.isEmpty ? duplicate.kindRaw : canonical.kindRaw
        if canonical.tmdbID == 0 { canonical.tmdbID = duplicate.tmdbID }
        canonical.traktID = canonical.traktID ?? duplicate.traktID
        canonical.listedAt = newest([canonical.listedAt, duplicate.listedAt])
        canonical.remoteUpdatedAt = newest([canonical.remoteUpdatedAt, duplicate.remoteUpdatedAt])
        canonical.localUpdatedAt = max(canonical.localUpdatedAt, duplicate.localUpdatedAt)
        canonical.dirty = canonical.dirty || duplicate.dirty
    }

    private func watchedEventPreferredOver(_ lhs: WatchedEventRecord, _ rhs: WatchedEventRecord) -> Bool {
        let lhsScore = (lhs.traktHistoryID != nil ? 4 : 0) + (lhs.dirty ? 2 : 0) + (lhs.traktID != nil ? 1 : 0)
        let rhsScore = (rhs.traktHistoryID != nil ? 4 : 0) + (rhs.dirty ? 2 : 0) + (rhs.traktID != nil ? 1 : 0)
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func mergeWatchedEvent(_ canonical: WatchedEventRecord, with duplicate: WatchedEventRecord) {
        canonical.traktID = canonical.traktID ?? duplicate.traktID
        canonical.showTMDbID = canonical.showTMDbID ?? duplicate.showTMDbID
        canonical.showTraktID = canonical.showTraktID ?? duplicate.showTraktID
        canonical.seasonNumber = canonical.seasonNumber ?? duplicate.seasonNumber
        canonical.episodeNumber = canonical.episodeNumber ?? duplicate.episodeNumber
        canonical.traktHistoryID = canonical.traktHistoryID ?? duplicate.traktHistoryID
        canonical.dirty = canonical.dirty || duplicate.dirty
        canonical.tombstoned = canonical.tombstoned || duplicate.tombstoned
        canonical.createdAt = min(canonical.createdAt, duplicate.createdAt)
        canonical.updatedAt = max(canonical.updatedAt, duplicate.updatedAt)
        canonical.eventKey = WatchedEventRecord.makeEventKey(
            kind: canonical.mediaID.kind,
            tmdbID: canonical.tmdbID,
            traktID: canonical.traktID,
            watchedAt: canonical.watchedAt
        )
    }

    private func syncOperationPreferredOver(_ lhs: SyncOperationRecord, _ rhs: SyncOperationRecord) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        let lhsPriority = syncOperationPriority(lhs.status)
        let rhsPriority = syncOperationPriority(rhs.status)
        if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }
        return lhs.attemptCount < rhs.attemptCount
    }

    private func syncOperationPriority(_ status: SyncOperationStatus) -> Int {
        switch status {
        case .processing: return 4
        case .pending: return 3
        case .deadletter: return 2
        case .succeeded: return 1
        }
    }

    private func mergeSyncOperation(_ canonical: SyncOperationRecord, with duplicate: SyncOperationRecord, now: Date) {
        canonical.payload = canonical.payload.isEmpty ? duplicate.payload : canonical.payload
        canonical.kindRaw = canonical.kindRaw.isEmpty ? duplicate.kindRaw : canonical.kindRaw
        canonical.dedupeKey = canonical.dedupeKey ?? duplicate.dedupeKey
        canonical.lastAttemptAt = newest([canonical.lastAttemptAt, duplicate.lastAttemptAt])
        canonical.attemptCount = max(canonical.attemptCount, duplicate.attemptCount)
        if syncOperationPreferredOver(duplicate, canonical) {
            canonical.status = duplicate.status
            canonical.kindRaw = duplicate.kindRaw
            canonical.payload = duplicate.payload
            canonical.createdAt = duplicate.createdAt
        }
        if canonical.status == .processing && isClaimExpired(canonical, now: now) {
            canonical.status = .pending
            canonical.claimedByDeviceID = nil
            canonical.claimedAt = nil
        }
    }

    private func syncStatePreferredOver(_ lhs: SyncStateRecord, _ rhs: SyncStateRecord) -> Bool {
        let lhsDate = newest([lhs.lastSuccessfulPullAt, lhs.lastSuccessfulPushAt, lhs.lastSeenRemoteActivityAt]) ?? .distantPast
        let rhsDate = newest([rhs.lastSuccessfulPullAt, rhs.lastSuccessfulPushAt, rhs.lastSeenRemoteActivityAt]) ?? .distantPast
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        return lhs.initialBaselineComplete && !rhs.initialBaselineComplete
    }

    private func mergeSyncState(_ canonical: SyncStateRecord, with duplicate: SyncStateRecord) {
        canonical.accountKey = canonical.accountKey.isEmpty ? duplicate.accountKey : canonical.accountKey
        canonical.initialBaselineComplete = canonical.initialBaselineComplete || duplicate.initialBaselineComplete
        canonical.lastSuccessfulPullAt = newest([canonical.lastSuccessfulPullAt, duplicate.lastSuccessfulPullAt])
        canonical.lastSuccessfulPushAt = newest([canonical.lastSuccessfulPushAt, duplicate.lastSuccessfulPushAt])
        canonical.lastSeenRemoteActivityAt = newest([canonical.lastSeenRemoteActivityAt, duplicate.lastSeenRemoteActivityAt])
    }

    private func syncState(context: ModelContext) -> SyncStateRecord {
        let accountKey = TraktLinkStore.activeAccountKey ?? "default"
        if let existing = allSyncStates(context: context).first(where: { $0.accountKey == accountKey }) {
            return existing
        }
        let state = SyncStateRecord(accountKey: accountKey)
        context.insert(state)
        return state
    }

    private func eventDeduplicationKey(_ event: WatchedEventRecord) -> String {
        if let historyID = event.traktHistoryID {
            return "history:\(historyID)"
        }
        return WatchedEventRecord.makeEventKey(
            kind: event.mediaID.kind,
            tmdbID: event.tmdbID,
            traktID: event.traktID,
            watchedAt: event.watchedAt
        )
    }

    private func newest(_ values: [Date?]) -> Date? {
        values.compactMap { $0 }.max()
    }

    private func descriptiveError(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }
        return error.localizedDescription
    }

    private func isClaimExpired(_ operation: SyncOperationRecord, now: Date) -> Bool {
        guard let claimedAt = operation.claimedAt else { return true }
        return now.timeIntervalSince(claimedAt) > 300
    }

    private func allOperations(context: ModelContext) -> [SyncOperationRecord] {
        (try? context.fetch(FetchDescriptor<SyncOperationRecord>())) ?? []
    }

    private func allMedia(context: ModelContext) -> [MediaRecord] {
        (try? context.fetch(FetchDescriptor<MediaRecord>())) ?? []
    }

    private func allEpisodes(context: ModelContext) -> [EpisodeRecord] {
        (try? context.fetch(FetchDescriptor<EpisodeRecord>())) ?? []
    }

    private func allWatchlist(context: ModelContext) -> [WatchlistRecord] {
        (try? context.fetch(FetchDescriptor<WatchlistRecord>())) ?? []
    }

    private func allEvents(context: ModelContext) -> [WatchedEventRecord] {
        (try? context.fetch(FetchDescriptor<WatchedEventRecord>())) ?? []
    }

    private func allSyncStates(context: ModelContext) -> [SyncStateRecord] {
        (try? context.fetch(FetchDescriptor<SyncStateRecord>())) ?? []
    }

    private func operationRecord(id: UUID, context: ModelContext) -> SyncOperationRecord? {
        allOperations(context: context).first { $0.id == id }
    }

    private func watchlistRecord(for mediaID: MediaID, context: ModelContext) -> WatchlistRecord? {
        allWatchlist(context: context).first { $0.mediaKey == mediaID.stableKey }
    }

    private func eventRecord(kind: MediaKind, tmdbID: Int, watchedAt: Date?, context: ModelContext) -> WatchedEventRecord? {
        guard let watchedAt else { return nil }
        let expected = WatchedEventRecord.makeEventKey(kind: kind, tmdbID: tmdbID, traktID: nil, watchedAt: watchedAt)
        return allEvents(context: context).first {
            $0.eventKey == expected || ($0.mediaID.kind == kind && $0.tmdbID == tmdbID && $0.watchedAt == watchedAt)
        }
    }

    private func eventRecord(historyID: Int, context: ModelContext) -> WatchedEventRecord? {
        allEvents(context: context).first { $0.traktHistoryID == historyID }
    }

    private func upsertMediaFromWatchlist(mediaID: MediaID, title: String, year: Int?, context: ModelContext) {
        if let existing = allMedia(context: context).first(where: { $0.kind == mediaID.kind && $0.tmdbID == mediaID.tmdbID }) {
            existing.mediaKey = existing.mediaKey.isEmpty ? mediaID.stableKey : existing.mediaKey
            existing.traktID = mediaID.traktID ?? existing.traktID
            if existing.title.isEmpty { existing.title = title }
            existing.releaseDate = existing.releaseDate ?? year.flatMap { Calendar.current.date(from: DateComponents(year: $0)) }
            existing.updatedAt = .now
        } else {
            context.insert(
                MediaRecord(
                    kind: mediaID.kind,
                    tmdbID: mediaID.tmdbID,
                    traktID: mediaID.traktID,
                    title: title,
                    releaseDate: year.flatMap { Calendar.current.date(from: DateComponents(year: $0)) },
                    updatedAt: .now
                )
            )
        }
    }

    private func upsertEpisodeFromHistory(showTMDbID: Int,
                                          showTraktID: Int?,
                                          episode: TraktEpisodeDTO,
                                          context: ModelContext) {
        guard let season = episode.season, let number = episode.number, let tmdbID = episode.ids.tmdb else { return }
        if let existing = allEpisodes(context: context).first(where: { $0.tmdbID == tmdbID }) {
            existing.episodeKey = existing.episodeKey.isEmpty ? "ep:\(showTMDbID):S\(season):E\(number)" : existing.episodeKey
            existing.traktID = episode.ids.trakt ?? existing.traktID
            existing.showTraktID = showTraktID ?? existing.showTraktID
            existing.name = existing.name.isEmpty ? (episode.title ?? "Episode") : existing.name
            existing.updatedAt = .now
        } else {
            context.insert(
                EpisodeRecord(
                    showTMDbID: showTMDbID,
                    showTraktID: showTraktID,
                    tmdbID: tmdbID,
                    traktID: episode.ids.trakt,
                    seasonNumber: season,
                    episodeNumber: number,
                    name: episode.title ?? "Episode",
                    updatedAt: .now
                )
            )
        }
    }
}

typealias SyncRepository = SyncEngine

private actor SyncClaimCoordinator {
    func claimNextOperation(in persistence: Persistence,
                            deviceID: String,
                            accountKey: String,
                            claimExpiration: TimeInterval) throws -> UUID? {
        while true {
            let claimContext = persistence.makeContext()
            let claimTimestamp = Date()
            let operations = ((try? claimContext.fetch(FetchDescriptor<SyncOperationRecord>())) ?? [])
                .filter { operation in
                    guard operation.accountKey == accountKey else { return false }
                    if let nextAttemptAt = operation.nextAttemptAt, nextAttemptAt > claimTimestamp { return false }
                    switch operation.status {
                    case .pending:
                        return true
                    case .processing:
                        guard let claimedAt = operation.claimedAt else { return true }
                        return claimTimestamp.timeIntervalSince(claimedAt) > claimExpiration
                    default:
                        return false
                    }
                }
                .sorted(by: { $0.createdAt < $1.createdAt })

            guard let candidate = operations.first else {
                return nil
            }

            candidate.claimedByDeviceID = deviceID
            candidate.claimedAt = claimTimestamp
            candidate.status = .processing
            try claimContext.save()

            let verifyContext = persistence.makeContext()
            let verified = ((try? verifyContext.fetch(FetchDescriptor<SyncOperationRecord>())) ?? [])
                .first { $0.id == candidate.id }

            if let verified,
               verified.claimedByDeviceID == deviceID,
               verified.status == .processing {
                return verified.id
            }
        }
    }
}
