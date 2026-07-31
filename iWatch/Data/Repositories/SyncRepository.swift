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
    private let resetGate: AppDataResetGate

    private let suspiciousWatchlistRemovalThreshold = 25
    private let completedOperationRetention: TimeInterval = 24 * 60 * 60
    private let deadletterRetention: TimeInterval = 30 * 24 * 60 * 60

    private static let claimCoordinator = SyncClaimCoordinator()

    private var lastRunErrorDescription: String?

    init(persistence: Persistence,
         trakt: any TraktSyncing,
         deviceIdentityStore: DeviceIdentityStore,
         resetGate: AppDataResetGate = AppDataResetGate()) {
        self.persistence = persistence
        self.trakt = trakt
        self.deviceIdentityStore = deviceIdentityStore
        self.resetGate = resetGate
    }

    func ensureInitialBaseline(progress: (@MainActor @Sendable (SyncProgress) async -> Void)? = nil) async throws {
        let token = await trakt.currentToken()
        guard token != nil else { return }

        let context = persistence.makeContext()
        try discardStaleGenerationRecords(context: context)
        let state = syncState(context: context)
        guard !state.initialBaselineComplete else { return }

        try await pullAndMerge(into: context, state: state, initialBaseline: true, progress: progress)
        state.initialBaselineComplete = true
        try context.save()
    }

    @discardableResult
    func run(reason: SyncReason,
             progress: (@MainActor @Sendable (SyncProgress) async -> Void)? = nil) async -> Bool {
        guard await resetGate.allowsLibraryWork() else { return false }
        do {
            lastRunErrorDescription = nil

            await progress?(.checkingLocalData)

            let repairContext = persistence.makeContext()
            _ = try performIntegrityRepair(context: repairContext, now: Date())
            try repairContext.save()

            try await ensureInitialBaseline(progress: progress)

            let pullContext = persistence.makeContext()
            let state = syncState(context: pullContext)
            try await pullAndMerge(into: pullContext, state: state, initialBaseline: false, progress: progress)
            try pullContext.save()

            let pendingCount = allOperations(context: persistence.makeContext())
                .filter { $0.status == .pending || $0.status == .processing }
                .count
            await progress?(.uploadingChanges(pendingCount))
            try await pushPendingOperations()
            await progress?(.complete)
            return true
        } catch {
            lastRunErrorDescription = descriptiveError(error)
            await progress?(.failed(lastRunErrorDescription ?? "Sync failed."))
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
        let watchlist = allWatchlist(context: context).filter(\.isInWatchlist)
        let history = allEvents(context: context).filter { !$0.tombstoned }

        return SyncDiagnostics(
            initialBaselineComplete: state.initialBaselineComplete,
            importedMovieCount: watchlist.filter { $0.mediaID.kind == .movie }.count,
            importedShowCount: watchlist.filter { $0.mediaID.kind == .show }.count,
            importedHistoryCount: history.count,
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

    func beginDataReset() async {
        await resetGate.beginReset()
    }

    func endDataReset() async {
        await resetGate.endReset()
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
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)
        context.insert(SyncOperationRecord(kind: kind, payload: data, generationID: generationID))
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
        _ = LibraryGenerationPolicy.rotateGeneration(in: context)

        for operation in rawOperations(context: context) {
            context.delete(operation)
        }
        for row in rawWatchlist(context: context) {
            context.delete(row)
        }
        for event in rawEvents(context: context) {
            context.delete(event)
        }
        for state in rawSyncStates(context: context) {
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

    @discardableResult
    func eraseAllAppData() throws -> Date {
        let context = persistence.makeContext()
        let resetAt = Date()

        _ = LibraryGenerationPolicy.rotateGeneration(in: context, at: resetAt)

        for media in rawMedia(context: context) {
            context.delete(media)
        }
        for episode in rawEpisodes(context: context) {
            context.delete(episode)
        }
        for operation in rawOperations(context: context) {
            context.delete(operation)
        }
        for row in rawWatchlist(context: context) {
            context.delete(row)
        }
        for event in rawEvents(context: context) {
            context.delete(event)
        }
        for state in rawSyncStates(context: context) {
            context.delete(state)
        }

        lastRunErrorDescription = nil
        try context.save()
        return resetAt
    }

    func requestCloudResetConfirmation() throws -> Date {
        let context = persistence.makeContext()
        let now = Date()
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)
        let markers = (try? context.fetch(FetchDescriptor<LibraryGenerationRecord>())) ?? []
        let marker = markers.max(by: { $0.changedAt < $1.changedAt })
            ?? LibraryGenerationRecord(
                generationID: generationID,
                changedAt: .distantPast
            )
        if marker.modelContext == nil {
            context.insert(marker)
        }
        marker.changedAt = now
        try discardStaleGenerationRecords(context: context)
        try context.save()
        return now
    }

    private func pullAndMerge(into context: ModelContext,
                              state: SyncStateRecord,
                              initialBaseline: Bool,
                              progress: (@MainActor @Sendable (SyncProgress) async -> Void)? = nil) async throws {
        let previousRelevantActivityAt = state.lastSeenRemoteActivityAt
        let remoteActivities = try? await trakt.getLastActivities()
        let shouldPullWatchlist = initialBaseline || shouldPullWatchlist(remoteActivities, previousRelevantActivityAt: previousRelevantActivityAt)
        let shouldPullHistory = initialBaseline
            || state.lastSuccessfulPullAt == nil
            || shouldPullHistory(remoteActivities, previousRelevantActivityAt: previousRelevantActivityAt)

        if shouldPullWatchlist { await progress?(.downloadingWatchlist(0)) }
        let remoteWatchlist = shouldPullWatchlist
            ? try await trakt.getWatchlist { count in await progress?(.downloadingWatchlist(count)) }
            : []
        if shouldPullHistory { await progress?(.downloadingHistory(0)) }
        let remoteHistory = shouldPullHistory
            ? try await trakt.getHistory(startAt: initialBaseline ? nil : state.lastSuccessfulPullAt) { count in
                await progress?(.downloadingHistory(count))
            }
            : []
        await progress?(.downloadingShowProgress)
        let activeShowProgress = try await trakt.getActiveShowProgress()
        if shouldPullWatchlist || shouldPullHistory {
            await progress?(.saving(watchlistItems: remoteWatchlist.count, historyItems: remoteHistory.count))
        }
        let now = Date()

        if shouldPullHistory {
            try mergeHistory(remoteHistory, context: context, now: now)
        }
        mergeActiveShowProgress(activeShowProgress, context: context, now: now)

        if shouldPullWatchlist {
            try mergeWatchlist(
                remoteWatchlist,
                context: context,
                now: now,
                allowRemoteRemoval: !initialBaseline,
                remoteUpdatedAt: remoteActivities?.watchlistActivityAt,
                activeShowProgress: activeShowProgress
            )
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
                    operation.nextAttemptAt = attemptedAt.addingTimeInterval(retryDelay(forAttempt: operation.attemptCount, error: error))
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
        if case .rateLimited = error as? AppError { return true }
        return true
    }

    private func retryDelay(forAttempt attempt: Int, error: Error) -> TimeInterval {
        if case let .rateLimited(retryAfter) = error as? AppError, let retryAfter {
            return max(retryAfter, 1)
        }
        return min(pow(2, Double(max(attempt - 1, 0))) * 30, 30 * 60)
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
                                remoteUpdatedAt: Date?,
                                activeShowProgress: [TraktShowProgressDTO]) throws {
        var remoteKeys = Set<String>()
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)
        let existingWatchlist = allWatchlist(context: context)
        var watchlistByKey = Dictionary(
            existingWatchlist.map { ($0.mediaKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var mediaByKey = Dictionary(
            allMedia(context: context).map { (mediaLookupKey(kind: $0.kind, tmdbID: $0.tmdbID), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for item in remoteItems {
            switch item.type {
            case .movie:
                guard let movie = item.movie, let tmdbID = movie.ids.tmdb else { continue }
                let mediaID = MediaID(kind: .movie, id: tmdbID, traktID: movie.ids.trakt)
                remoteKeys.insert(mediaID.stableKey)
                upsertMediaIndexed(mediaID: mediaID, title: movie.title ?? "Unknown", year: movie.year, context: context, mediaByKey: &mediaByKey)
                let existing = watchlistByKey[mediaID.stableKey]
                let row = existing ?? WatchlistRecord(
                    mediaID: mediaID,
                    isInWatchlist: true,
                    generationID: generationID
                )
                if existing == nil {
                    context.insert(row)
                    watchlistByKey[mediaID.stableKey] = row
                }
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
                upsertMediaIndexed(mediaID: mediaID, title: show.title ?? "Unknown", year: show.year, context: context, mediaByKey: &mediaByKey)
                let existing = watchlistByKey[mediaID.stableKey]
                let row = existing ?? WatchlistRecord(
                    mediaID: mediaID,
                    isInWatchlist: true,
                    generationID: generationID
                )
                if existing == nil {
                    context.insert(row)
                    watchlistByKey[mediaID.stableKey] = row
                }
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

        let activeShowKeys = Set(activeShowProgress.compactMap { item -> String? in
            guard item.progress.completed > 0,
                  item.progress.completed < item.progress.aired,
                  let tmdbID = item.show.ids.tmdb else { return nil }
            return MediaID(kind: .show, id: tmdbID, traktID: item.show.ids.trakt).stableKey
        })
        let historyKeys = historyBackedMediaKeys(context: context)
        let missingRows = existingWatchlist.filter {
            $0.isInWatchlist
                && !$0.dirty
                && !remoteKeys.contains($0.mediaKey)
                && !activeShowKeys.contains($0.mediaKey)
                && !historyKeys.contains($0.mediaKey)
        }

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

    private func mergeActiveShowProgress(_ remoteItems: [TraktShowProgressDTO],
                                         context: ModelContext,
                                         now: Date) {
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)
        var watchlistByKey = Dictionary(
            allWatchlist(context: context).map { ($0.mediaKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var mediaByKey = Dictionary(
            allMedia(context: context).map { (mediaLookupKey(kind: $0.kind, tmdbID: $0.tmdbID), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for item in remoteItems {
            guard item.progress.completed > 0,
                  item.progress.completed < item.progress.aired,
                  let tmdbID = item.show.ids.tmdb else { continue }

            let mediaID = MediaID(kind: .show, id: tmdbID, traktID: item.show.ids.trakt)
            upsertMediaIndexed(
                mediaID: mediaID,
                title: item.show.title ?? "Unknown",
                year: item.show.year,
                context: context,
                mediaByKey: &mediaByKey
            )

            // A persisted false row is an explicit iWatch unfollow. Progress must
            // not silently undo that choice on the next Trakt pull.
            guard watchlistByKey[mediaID.stableKey] == nil else { continue }
            let record = WatchlistRecord(
                mediaID: mediaID,
                isInWatchlist: true,
                listedAt: item.progress.lastWatchedAt,
                localUpdatedAt: now,
                remoteUpdatedAt: item.progress.lastWatchedAt ?? now,
                dirty: false,
                generationID: generationID
            )
            context.insert(record)
            watchlistByKey[mediaID.stableKey] = record
        }
    }

    private func historyBackedMediaKeys(context: ModelContext) -> Set<String> {
        Set(allEvents(context: context).compactMap { event -> String? in
            guard !event.tombstoned else { return nil }
            switch event.mediaID.kind {
            case .movie:
                return MediaID(kind: .movie, id: event.tmdbID, traktID: event.traktID).stableKey
            case .episode:
                guard let showTMDbID = event.showTMDbID else { return nil }
                return MediaID(kind: .show, id: showTMDbID, traktID: event.showTraktID).stableKey
            default:
                return nil
            }
        })
    }

    private func mergeHistory(_ remoteItems: [TraktHistoryItemDTO],
                              context: ModelContext,
                              now: Date) throws {
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)
        var eventsByNaturalKey: [String: WatchedEventRecord] = [:]
        var eventsByHistoryID: [Int: WatchedEventRecord] = [:]
        var mediaByKey: [String: MediaRecord] = [:]
        var episodesByTMDbID: [Int: EpisodeRecord] = [:]

        for event in allEvents(context: context) {
            eventsByNaturalKey[historyNaturalKey(
                kind: event.mediaID.kind,
                tmdbID: event.tmdbID,
                watchedAt: event.watchedAt
            ), default: event] = event
            if let historyID = event.traktHistoryID {
                eventsByHistoryID[historyID, default: event] = event
            }
        }
        for media in allMedia(context: context) {
            mediaByKey[mediaLookupKey(kind: media.kind, tmdbID: media.tmdbID), default: media] = media
        }
        for episode in allEpisodes(context: context) {
            episodesByTMDbID[episode.tmdbID, default: episode] = episode
        }

        for item in remoteItems {
            guard let watchedAt = item.watchedAt else { continue }

            switch item.type {
            case .movie:
                guard let movie = item.movie, let tmdbID = movie.ids.tmdb else { continue }
                let naturalKey = historyNaturalKey(kind: .movie, tmdbID: tmdbID, watchedAt: watchedAt)
                let existing = eventsByNaturalKey[naturalKey] ?? eventsByHistoryID[item.id]
                let event = existing ?? WatchedEventRecord(
                    kind: .movie,
                    tmdbID: tmdbID,
                    traktID: movie.ids.trakt,
                    watchedAt: watchedAt,
                    traktHistoryID: item.id,
                    dirty: false,
                    tombstoned: false,
                    createdAt: now,
                    updatedAt: now,
                    generationID: generationID
                )
                if existing == nil {
                    context.insert(event)
                    eventsByNaturalKey[naturalKey] = event
                    eventsByHistoryID[item.id] = event
                }
                if event.tombstoned && event.dirty {
                    continue
                }
                event.eventKey = WatchedEventRecord.makeEventKey(kind: .movie, tmdbID: tmdbID, traktID: movie.ids.trakt, watchedAt: watchedAt)
                event.traktID = movie.ids.trakt ?? event.traktID
                event.traktHistoryID = item.id
                event.dirty = false
                event.tombstoned = false
                event.updatedAt = now
                upsertMediaIndexed(
                    mediaID: MediaID(kind: .movie, id: tmdbID, traktID: movie.ids.trakt),
                    title: movie.title ?? "Unknown",
                    year: movie.year,
                    context: context,
                    mediaByKey: &mediaByKey
                )
            case .episode:
                guard let episode = item.episode, let tmdbID = episode.ids.tmdb else { continue }
                let showTMDbID = item.show?.ids.tmdb
                let naturalKey = historyNaturalKey(kind: .episode, tmdbID: tmdbID, watchedAt: watchedAt)
                let existing = eventsByNaturalKey[naturalKey] ?? eventsByHistoryID[item.id]
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
                    updatedAt: now,
                    generationID: generationID
                )
                if existing == nil {
                    context.insert(event)
                    eventsByNaturalKey[naturalKey] = event
                    eventsByHistoryID[item.id] = event
                }
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
                    upsertMediaIndexed(
                        mediaID: MediaID(kind: .show, id: showTMDbID, traktID: item.show?.ids.trakt),
                        title: item.show?.title ?? "Unknown",
                        year: item.show?.year,
                        context: context,
                        mediaByKey: &mediaByKey
                    )
                    upsertEpisodeFromHistory(
                        showTMDbID: showTMDbID,
                        showTraktID: item.show?.ids.trakt,
                        episode: episode,
                        context: context,
                        episodesByTMDbID: &episodesByTMDbID
                    )
                }
            default:
                continue
            }
        }
    }

    private func historyNaturalKey(kind: MediaKind, tmdbID: Int, watchedAt: Date) -> String {
        "\(kind.rawValue):\(tmdbID):\(watchedAt.timeIntervalSinceReferenceDate.bitPattern)"
    }

    private func mediaLookupKey(kind: MediaKind, tmdbID: Int) -> String {
        "\(kind.rawValue):\(tmdbID)"
    }

    private func upsertMediaIndexed(mediaID: MediaID,
                                    title: String,
                                    year: Int?,
                                    context: ModelContext,
                                    mediaByKey: inout [String: MediaRecord]) {
        let key = mediaLookupKey(kind: mediaID.kind, tmdbID: mediaID.tmdbID)
        if let existing = mediaByKey[key] {
            existing.mediaKey = existing.mediaKey.isEmpty ? mediaID.stableKey : existing.mediaKey
            existing.traktID = mediaID.traktID ?? existing.traktID
            if existing.title.isEmpty { existing.title = title }
            existing.releaseDate = existing.releaseDate ?? year.flatMap { Calendar.current.date(from: DateComponents(year: $0)) }
            existing.updatedAt = .now
        } else {
            let record = MediaRecord(
                kind: mediaID.kind,
                tmdbID: mediaID.tmdbID,
                traktID: mediaID.traktID,
                title: title,
                releaseDate: year.flatMap { Calendar.current.date(from: DateComponents(year: $0)) },
                updatedAt: .now
            )
            context.insert(record)
            mediaByKey[key] = record
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
        let state = SyncStateRecord(
            accountKey: accountKey,
            generationID: LibraryGenerationPolicy.currentGeneration(in: context)
        )
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
        current(rawOperations(context: context), in: context, generation: \.generationID)
    }

    private func allMedia(context: ModelContext) -> [MediaRecord] {
        (try? context.fetch(FetchDescriptor<MediaRecord>())) ?? []
    }

    private func allEpisodes(context: ModelContext) -> [EpisodeRecord] {
        (try? context.fetch(FetchDescriptor<EpisodeRecord>())) ?? []
    }

    private func allWatchlist(context: ModelContext) -> [WatchlistRecord] {
        current(rawWatchlist(context: context), in: context, generation: \.generationID)
    }

    private func allEvents(context: ModelContext) -> [WatchedEventRecord] {
        current(rawEvents(context: context), in: context, generation: \.generationID)
    }

    private func allSyncStates(context: ModelContext) -> [SyncStateRecord] {
        current(rawSyncStates(context: context), in: context, generation: \.generationID)
    }

    private func rawOperations(context: ModelContext) -> [SyncOperationRecord] {
        (try? context.fetch(FetchDescriptor<SyncOperationRecord>())) ?? []
    }

    private func rawMedia(context: ModelContext) -> [MediaRecord] {
        (try? context.fetch(FetchDescriptor<MediaRecord>())) ?? []
    }

    private func rawEpisodes(context: ModelContext) -> [EpisodeRecord] {
        (try? context.fetch(FetchDescriptor<EpisodeRecord>())) ?? []
    }

    private func rawWatchlist(context: ModelContext) -> [WatchlistRecord] {
        (try? context.fetch(FetchDescriptor<WatchlistRecord>())) ?? []
    }

    private func rawEvents(context: ModelContext) -> [WatchedEventRecord] {
        (try? context.fetch(FetchDescriptor<WatchedEventRecord>())) ?? []
    }

    private func rawSyncStates(context: ModelContext) -> [SyncStateRecord] {
        (try? context.fetch(FetchDescriptor<SyncStateRecord>())) ?? []
    }

    private func current<Record>(
        _ records: [Record],
        in context: ModelContext,
        generation: KeyPath<Record, String>
    ) -> [Record] {
        let currentGeneration = LibraryGenerationPolicy.currentGeneration(in: context)
        return records.filter {
            LibraryGenerationPolicy.belongsToCurrentGeneration(
                $0[keyPath: generation],
                current: currentGeneration
            )
        }
    }

    private func discardStaleGenerationRecords(context: ModelContext) throws {
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)
        for record in rawOperations(context: context)
        where !LibraryGenerationPolicy.belongsToCurrentGeneration(record.generationID, current: generationID) {
            context.delete(record)
        }
        for record in rawWatchlist(context: context)
        where !LibraryGenerationPolicy.belongsToCurrentGeneration(record.generationID, current: generationID) {
            context.delete(record)
        }
        for record in rawEvents(context: context)
        where !LibraryGenerationPolicy.belongsToCurrentGeneration(record.generationID, current: generationID) {
            context.delete(record)
        }
        for record in rawSyncStates(context: context)
        where !LibraryGenerationPolicy.belongsToCurrentGeneration(record.generationID, current: generationID) {
            context.delete(record)
        }
        if context.hasChanges {
            try context.save()
        }
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

    private func upsertEpisodeFromHistory(showTMDbID: Int,
                                          showTraktID: Int?,
                                          episode: TraktEpisodeDTO,
                                          context: ModelContext,
                                          episodesByTMDbID: inout [Int: EpisodeRecord]) {
        guard let season = episode.season, let number = episode.number, let tmdbID = episode.ids.tmdb else { return }
        if let existing = episodesByTMDbID[tmdbID] {
            existing.episodeKey = existing.episodeKey.isEmpty ? "ep:\(showTMDbID):S\(season):E\(number)" : existing.episodeKey
            existing.traktID = episode.ids.trakt ?? existing.traktID
            existing.showTraktID = showTraktID ?? existing.showTraktID
            existing.name = existing.name.isEmpty ? (episode.title ?? "Episode") : existing.name
            existing.updatedAt = .now
        } else {
            let record = EpisodeRecord(
                showTMDbID: showTMDbID,
                showTraktID: showTraktID,
                tmdbID: tmdbID,
                traktID: episode.ids.trakt,
                seasonNumber: season,
                episodeNumber: number,
                name: episode.title ?? "Episode",
                updatedAt: .now
            )
            context.insert(record)
            episodesByTMDbID[tmdbID] = record
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
