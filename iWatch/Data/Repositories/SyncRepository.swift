import Foundation
import SwiftData

// MARK: - Sync State

enum SyncReason: String, Sendable {
    case localMutation
    case appLaunch
    case foreground
    case userInitiated
    case background
}

// MARK: - Sync Engine

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
    private let accountKeyProvider: @Sendable () -> String?
    private let reconciliationSchedule: HistoryReconciliationSchedule

    private let suspiciousWatchlistRemovalThreshold = 25
    private let completedOperationRetention: TimeInterval = 24 * 60 * 60
    private let deadletterRetention: TimeInterval = 30 * 24 * 60 * 60

    private static let claimCoordinator = SyncClaimCoordinator()

    private var lastRunErrorDescription: String?
    private var isRunning = false

    init(persistence: Persistence,
         trakt: any TraktSyncing,
         deviceIdentityStore: DeviceIdentityStore,
         resetGate: AppDataResetGate = AppDataResetGate(),
         accountKeyProvider: @escaping @Sendable () -> String? = { TraktLinkStore.activeAccountKey },
         reconciliationSchedule: HistoryReconciliationSchedule? = nil) {
        self.persistence = persistence
        self.trakt = trakt
        self.deviceIdentityStore = deviceIdentityStore
        self.resetGate = resetGate
        self.accountKeyProvider = accountKeyProvider
        self.reconciliationSchedule = reconciliationSchedule ?? HistoryReconciliationSchedule(defaults: persistence.modelContainer.configurations.first?.isStoredInMemoryOnly == true ? nil : .standard)
    }

    // MARK: Sync Lifecycle

    func ensureInitialBaseline(progress: (@MainActor @Sendable (SyncProgress) async -> Void)? = nil) async throws {
        let token = await trakt.currentToken()
        guard token != nil else { return }

        let context = persistence.makeContext()
        try discardStaleGenerationRecords(context: context)
        let state = syncState(context: context)
        guard !state.initialBaselineComplete else { return }

        try await pullAndMerge(
            into: context,
            state: state,
            initialBaseline: true,
            reconcileRemoteHistory: false,
            progress: progress
        )
        state.initialBaselineComplete = true
        try context.save()
        reconciliationSchedule.recordFullSync(account: state.accountKey)
    }

    @discardableResult
    func run(reason: SyncReason,
             progress: (@MainActor @Sendable (SyncProgress) async -> Void)? = nil) async -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        defer { isRunning = false }
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
            let reconcileHistory = reconciliationSchedule.shouldReconcile(account: state.accountKey, reason: reason, previousPull: state.lastSuccessfulPullAt)
            try await pullAndMerge(
                into: pullContext,
                state: state,
                initialBaseline: false,
                reconcileRemoteHistory: reconcileHistory,
                progress: progress
            )
            try pullContext.save()
            if reconcileHistory { reconciliationSchedule.recordFullSync(account: state.accountKey) }

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
        var operation = operation
        operation.originDeviceID = await deviceIdentityStore.currentDeviceID()
        operation.mutationAt = Date()
        let data = try SyncPayloadCodec.encoder.encode(operation)
        let generationID = LibraryGenerationPolicy.currentGeneration(in: context)
        context.insert(SyncOperationRecord(kind: kind, payload: data, accountKey: accountKeyProvider() ?? "", generationID: generationID))
        try context.save()
    }

    @discardableResult
    // MARK: Maintenance

    func retryDeadletterOperations() async throws -> Int {
        guard let account = accountKeyProvider() else { return 0 }
        let device = await deviceIdentityStore.currentDeviceID()
        let context = persistence.makeContext()
        let deadletters = allOperations(context: context).filter {
            $0.status == .deadletter && $0.accountKey == account
                && (try? SyncPayloadCodec.decoder.decode(SyncOperationPayload.self, from: $0.payload).originDeviceID) == device
        }

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
        for disposition in rawShowDispositions(context: context) {
            context.delete(disposition)
        }
        for state in rawSyncStates(context: context) {
            context.delete(state)
        }

        lastRunErrorDescription = nil
        try context.save()
    }

    /// Explicit recovery only: the user must stop syncing on the previous device.
    func recoverPendingUploads() async throws -> Int {
        guard !isRunning, let account = accountKeyProvider() else { return 0 }
        let device = await deviceIdentityStore.currentDeviceID()
        let context = persistence.makeContext()
        let operations = allOperations(context: context).filter {
            $0.accountKey == account || $0.accountKey.isEmpty
        }
        guard !operations.contains(where: {
            $0.status == .processing && Date().timeIntervalSince($0.claimedAt ?? .now) < 300
        }) else { throw AppError.unknown("An upload may still be running. Stop syncing on the other device and try again later.") }
        var count = 0
        for operation in operations where operation.status != .succeeded {
            var payload = try SyncPayloadCodec.decoder.decode(SyncOperationPayload.self, from: operation.payload)
            payload.originDeviceID = device
            operation.payload = try SyncPayloadCodec.encoder.encode(payload)
            operation.accountKey = account
            operation.status = .pending
            operation.claimedAt = nil
            operation.claimedByDeviceID = nil
            operation.nextAttemptAt = nil
            operation.attemptCount = 0
            count += 1
        }
        try context.save()
        return count
    }

    func assignUnlinkedOperations(to accountKey: String) async throws {
        let deviceID = await deviceIdentityStore.currentDeviceID()
        let context = persistence.makeContext()
        for operation in allOperations(context: context) where operation.accountKey.isEmpty {
            guard let payload = try? SyncPayloadCodec.decoder.decode(SyncOperationPayload.self, from: operation.payload),
                  payload.originDeviceID == deviceID else { continue }
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
        for disposition in rawShowDispositions(context: context) {
            context.delete(disposition)
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

    // MARK: Pull and Push

    private func pullAndMerge(into context: ModelContext,
                              state: SyncStateRecord,
                              initialBaseline: Bool,
                              reconcileRemoteHistory: Bool,
                              progress: (@MainActor @Sendable (SyncProgress) async -> Void)? = nil) async throws {
        let expectedAccount = accountKeyProvider()
        let expectedGeneration = LibraryGenerationPolicy.currentGeneration(in: context)
        let previousRelevantActivityAt = state.lastSeenRemoteActivityAt
        let remoteActivities = try? await trakt.getLastActivities()
        let shouldPullWatchlist = initialBaseline || shouldPullWatchlist(remoteActivities, previousRelevantActivityAt: previousRelevantActivityAt)
        let shouldPullHistory = reconcileRemoteHistory
            || initialBaseline
            || state.lastSuccessfulPullAt == nil
            || shouldPullHistory(remoteActivities, previousRelevantActivityAt: previousRelevantActivityAt)

        if shouldPullWatchlist { await progress?(.downloadingWatchlist(0)) }
        let remoteWatchlist = shouldPullWatchlist
            ? try await trakt.getWatchlist { count in await progress?(.downloadingWatchlist(count)) }
            : []
        if shouldPullHistory { await progress?(.downloadingHistory(0)) }
        let remoteHistory = shouldPullHistory
            ? try await trakt.getHistory(
                startAt: (initialBaseline || reconcileRemoteHistory) ? nil : state.lastSuccessfulPullAt
            ) { count in
                await progress?(.downloadingHistory(count))
            }
            : []
        if shouldPullWatchlist || shouldPullHistory {
            await progress?(.saving(watchlistItems: remoteWatchlist.count, historyItems: remoteHistory.count))
        }
        guard await resetGate.allowsLibraryWork(), accountKeyProvider() == expectedAccount,
              LibraryGenerationPolicy.currentGeneration(in: persistence.makeContext()) == expectedGeneration else { throw CancellationError() }
        let now = Date()

        if shouldPullHistory {
            try mergeHistory(
                remoteHistory,
                context: context,
                now: now,
                reconcileRemoteDeletions: reconcileRemoteHistory
            )
        }
        if shouldPullWatchlist {
            try mergeWatchlist(
                remoteWatchlist,
                context: context,
                now: now,
                allowRemoteRemoval: !initialBaseline,
                remoteUpdatedAt: remoteActivities?.watchlistActivityAt
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
        guard let accountKey = accountKeyProvider() else { return }
        let deviceID = await deviceIdentityStore.currentDeviceID()
        let now = Date()
        while let operationID = try await claimNextOperation(deviceID: deviceID, accountKey: accountKey) {
            guard accountKeyProvider() == accountKey else { throw CancellationError() }
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
                guard await resetGate.allowsLibraryWork() else { throw CancellationError() }
                if error is CancellationError {
                    operation.status = .pending
                    operation.claimedByDeviceID = nil
                    operation.claimedAt = nil
                    try processContext.save()
                    throw error
                }
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
        if let reconciliation = error as? HistoryReconciliationError { return reconciliation != .ambiguous }
        return true
    }

    private func retryDelay(forAttempt attempt: Int, error: Error) -> TimeInterval {
        if case let .rateLimited(retryAfter) = error as? AppError, let retryAfter {
            return max(retryAfter, 1)
        }
        return min(pow(2, Double(max(attempt - 1, 0))) * 30, 30 * 60)
    }

    private func canAcknowledge(_ operation: SyncOperationRecord, in context: ModelContext) -> Bool {
        let generation = LibraryGenerationPolicy.currentGeneration(in: context)
        guard LibraryGenerationPolicy.belongsToCurrentGeneration(operation.generationID, current: generation) else { return false }
        guard let key = operation.dedupeKey else { return true }
        return !allOperations(context: context).contains {
            $0.id != operation.id && $0.dedupeKey == key && $0.status != .succeeded
        }
    }

    private func process(operation: SyncOperationRecord, context: ModelContext) async throws {
        let payload = try SyncPayloadCodec.decoder.decode(SyncOperationPayload.self, from: operation.payload)
        let sentAt = payload.mutationAt ?? operation.createdAt
        guard accountKeyProvider() == operation.accountKey else { throw CancellationError() }

        switch operation.kind {
        case .addWatchlist:
            if let mediaID = payload.mediaKind.flatMap({ kind in payload.tmdbID.map { MediaID(kind: kind, id: $0, traktID: payload.traktID) } }) {
                try await trakt.addToWatchlist([mediaID])
                guard await resetGate.allowsLibraryWork(), accountKeyProvider() == operation.accountKey else { throw CancellationError() }
                let acknowledgement = persistence.makeContext()
                if let row = watchlistRecord(for: mediaID, context: acknowledgement), row.localUpdatedAt <= sentAt, canAcknowledge(operation, in: acknowledgement) {
                    row.dirty = false
                    row.isInWatchlist = true
                    row.remoteUpdatedAt = Date()
                    try acknowledgement.save()
                }
            }
        case .removeWatchlist:
            if let mediaID = payload.mediaKind.flatMap({ kind in payload.tmdbID.map { MediaID(kind: kind, id: $0, traktID: payload.traktID) } }) {
                try await trakt.removeFromWatchlist([mediaID])
                guard await resetGate.allowsLibraryWork(), accountKeyProvider() == operation.accountKey else { throw CancellationError() }
                let acknowledgement = persistence.makeContext()
                if let row = watchlistRecord(for: mediaID, context: acknowledgement), row.localUpdatedAt <= sentAt, canAcknowledge(operation, in: acknowledgement) {
                    row.dirty = false
                    row.isInWatchlist = false
                    row.remoteUpdatedAt = Date()
                    try acknowledgement.save()
                }
            }
        case .addHistory:
            try await processHistoryAddition(operation: operation, payload: payload, context: context)
        case .removeHistory:
            try await processHistoryRemoval(operation: operation, payload: payload)

        }

        try context.save()
    }

    private func validateHistoryContext(_ operation: SyncOperationRecord) async throws {
        guard await resetGate.allowsLibraryWork(), accountKeyProvider() == operation.accountKey,
              LibraryGenerationPolicy.belongsToCurrentGeneration(operation.generationID,
                current: LibraryGenerationPolicy.currentGeneration(in: persistence.makeContext())) else { throw CancellationError() }
    }

    private func matchingRemoteHistory(_ payload: SyncOperationPayload, operation: SyncOperationRecord) async throws -> [TraktHistoryItemDTO] {
        guard let date = payload.watchedAt, payload.tmdbID != nil else { throw HistoryReconciliationError.ambiguous }
        // Trakt normalizes watched_at to the start of its UTC minute.
        let minute = HistoryMatchPolicy.remoteMinute(date)
        let history = try await trakt.getHistory(startAt: minute.addingTimeInterval(-1), endAt: minute.addingTimeInterval(60))
        try await validateHistoryContext(operation)
        return history.filter { HistoryMatchPolicy.matches(payload, remote: $0) }
    }

    private func processHistoryAddition(operation: SyncOperationRecord, payload original: SyncOperationPayload, context: ModelContext) async throws {
        var payload = original
        guard let kind = payload.mediaKind, let id = payload.tmdbID else { throw HistoryReconciliationError.ambiguous }
        let initial = eventRecord(kind: kind, tmdbID: id, watchedAt: payload.watchedAt, context: persistence.makeContext())
        let uncertain = payload.historyRequestStartedAt != nil || (operation.attemptCount > 0 && payload.historyRequestRejected != true)
        if !uncertain {
            // A removal queued before this request started cancels the add safely.
            guard let initial, !initial.tombstoned else {
                payload.historyKnownIDs = []
                payload.historyRequestRejected = true
                operation.payload = try SyncPayloadCodec.encoder.encode(payload)
                try context.save()
                return
            }
            // Establish which plays existed before this particular upload.
            payload.historyRequestRejected = true
            operation.payload = try SyncPayloadCodec.encoder.encode(payload)
            try context.save()
            payload.historyKnownIDs = try await matchingRemoteHistory(payload, operation: operation).map(\.id)
            payload.historyRequestStartedAt = Date()
            payload.historyRequestRejected = false
            operation.payload = try SyncPayloadCodec.encoder.encode(payload)
            try context.save() // Persist intent before sending a non-idempotent request.
            do { try await trakt.addToHistory([payload]) }
            catch {
                // An explicit rejection is safe to retry; timeouts/5xx/decoding failures are not.
                if case let .httpStatus(code, _) = error as? AppError, (400..<500).contains(code), code != 408 {
                    payload.historyRequestStartedAt = nil
                    payload.historyRequestRejected = true
                    operation.payload = try SyncPayloadCodec.encoder.encode(payload)
                    try context.save()
                } else if case .rateLimited = error as? AppError {
                    payload.historyRequestStartedAt = nil
                    payload.historyRequestRejected = true
                    operation.payload = try SyncPayloadCodec.encoder.encode(payload)
                    try context.save()
                }
                throw error
            }
        }
        guard let knownIDs = payload.historyKnownIDs else { throw HistoryReconciliationError.ambiguous }
        let matches = try await matchingRemoteHistory(payload, operation: operation).filter { !knownIDs.contains($0.id) }
        guard matches.count == 1, let remote = matches.first else {
            throw matches.isEmpty ? HistoryReconciliationError.unconfirmed : .ambiguous
        }
        let acknowledgement = persistence.makeContext()
        if let event = eventRecord(kind: kind, tmdbID: id, watchedAt: payload.watchedAt, context: acknowledgement) {
            guard event.traktHistoryID == nil || event.traktHistoryID == remote.id else { throw HistoryReconciliationError.ambiguous }
            // Imported replicas can have a newer bookkeeping timestamp without a newer local edit.
            let canClearDirty = !event.tombstoned
                && event.updatedAt <= (payload.mutationAt ?? operation.createdAt)
                && canAcknowledge(operation, in: acknowledgement)
            event.traktHistoryID = remote.id
            for duplicate in allEvents(context: acknowledgement) where duplicate !== event && duplicate.traktHistoryID == remote.id {
                mergeWatchedEvent(event, with: duplicate)
                acknowledgement.delete(duplicate)
            }
            if canClearDirty, !event.tombstoned {
                event.dirty = false
            }
            try acknowledgement.save()
        }
    }

    private func processHistoryRemoval(operation: SyncOperationRecord, payload: SyncOperationPayload) async throws {
        let read = persistence.makeContext()
        let event = payload.mediaKind.flatMap { kind in
            payload.tmdbID.flatMap { eventRecord(kind: kind, tmdbID: $0, watchedAt: payload.watchedAt, context: read) }
        }
        var historyID = payload.historyID ?? event?.traktHistoryID
        if historyID == nil {
            let relatedAdds = allOperations(context: read).filter {
                guard $0.kind == .addHistory, $0.accountKey == operation.accountKey,
                      let add = try? SyncPayloadCodec.decoder.decode(SyncOperationPayload.self, from: $0.payload) else { return false }
                return HistoryMatchPolicy.samePlay(payload, add)
            }
            guard relatedAdds.allSatisfy({ $0.status == .succeeded }) else { throw HistoryReconciliationError.waitingForAddition }
            let additions = try relatedAdds.map { try SyncPayloadCodec.decoder.decode(SyncOperationPayload.self, from: $0.payload) }
            guard !additions.isEmpty else { throw HistoryReconciliationError.ambiguous }
            let neverSent = additions.allSatisfy { $0.historyRequestRejected == true && $0.historyRequestStartedAt == nil }
            if !neverSent {
                guard additions.allSatisfy({ $0.historyKnownIDs != nil }) else { throw HistoryReconciliationError.ambiguous }
                let knownIDs = Set(additions.flatMap { $0.historyKnownIDs ?? [] })
                let matches = try await matchingRemoteHistory(payload, operation: operation).filter { !knownIDs.contains($0.id) }
                guard matches.count <= 1 else { throw HistoryReconciliationError.ambiguous }
                historyID = matches.first?.id
            }
        }
        if let historyID {
            try await validateHistoryContext(operation)
            try await trakt.removeFromHistory(historyIDs: [historyID])
        }
        try await validateHistoryContext(operation)
        let acknowledgement = persistence.makeContext()
        let removed = payload.mediaKind.flatMap { kind in
            payload.tmdbID.flatMap { eventRecord(kind: kind, tmdbID: $0, watchedAt: payload.watchedAt, context: acknowledgement) }
        } ?? historyID.flatMap { eventRecord(historyID: $0, context: acknowledgement) }
        if let removed, removed.tombstoned, removed.updatedAt <= (payload.mutationAt ?? operation.createdAt) {
            acknowledgement.delete(removed)
            try acknowledgement.save()
        }
    }

    // MARK: Remote Merge

    private func mergeWatchlist(_ remoteItems: [TraktWatchlistItemDTO],
                                context: ModelContext,
                                now: Date,
                                allowRemoteRemoval: Bool,
                                remoteUpdatedAt: Date?) throws {
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

        let missingRows = existingWatchlist.filter {
            $0.isInWatchlist
                && !$0.dirty
                && !remoteKeys.contains($0.mediaKey)
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

    private func mergeHistory(_ remoteItems: [TraktHistoryItemDTO],
                              context: ModelContext,
                              now: Date,
                              reconcileRemoteDeletions: Bool) throws {
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
                let local = eventsByNaturalKey[naturalKey]
                let existing = eventsByHistoryID[item.id] ?? (local?.traktHistoryID == nil ? local : nil)
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
                let local = eventsByNaturalKey[naturalKey]
                let existing = eventsByHistoryID[item.id] ?? (local?.traktHistoryID == nil ? local : nil)
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

        if reconcileRemoteDeletions {
            let remoteHistoryIDs = Set(remoteItems.map(\.id))
            let missingEvents = allEvents(context: context).filter {
                $0.traktHistoryID.map { !remoteHistoryIDs.contains($0) } == true && !$0.dirty
            }
            guard !remoteItems.isEmpty || missingEvents.isEmpty else {
                lastRunErrorDescription = "Skipped remote history removals because Trakt returned an empty history payload."
                return
            }
            for event in missingEvents {
                event.tombstoned = true
                event.updatedAt = now
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

    // MARK: Integrity Repair

    private func performIntegrityRepair(context: ModelContext, now: Date) throws -> SyncIntegrityRepairSummary {
        let mediaMerged = repairMediaDuplicates(context: context)
        let episodesMerged = repairEpisodeDuplicates(context: context)
        let watchlistMerged = repairWatchlistDuplicates(context: context)
        let watchedEventsMerged = repairWatchedEventDuplicates(context: context)
        let showDispositionsMerged = repairShowDispositionDuplicates(context: context)
        let operationsMerged = repairSyncOperationDuplicates(context: context, now: now)
        let syncStatesMerged = repairSyncStateDuplicates(context: context)
        let prunedCompletedOperations = pruneCompletedOperations(context: context, now: now)

        return SyncIntegrityRepairSummary(
            mediaMerged: mediaMerged,
            episodesMerged: episodesMerged,
            watchlistMerged: watchlistMerged,
            watchedEventsMerged: watchedEventsMerged,
            showDispositionsMerged: showDispositionsMerged,
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

    private func repairShowDispositionDuplicates(context: ModelContext) -> Int {
        let groups = Dictionary(grouping: allShowDispositions(context: context)) {
            $0.mediaKey.isEmpty ? "show:\($0.tmdbID)" : $0.mediaKey
        }
        var merged = 0

        for group in groups.values where group.count > 1 {
            let ordered = group.sorted { $0.updatedAt > $1.updatedAt }
            guard let canonical = ordered.first else { continue }
            canonical.mediaKey = canonical.mediaKey.isEmpty ? "show:\(canonical.tmdbID)" : canonical.mediaKey
            for duplicate in ordered.dropFirst() {
                canonical.traktID = canonical.traktID ?? duplicate.traktID
                context.delete(duplicate)
                merged += 1
            }
        }
        return merged
    }

    private func operationIdentity(_ operation: SyncOperationRecord) -> String {
        let owner = (try? SyncPayloadCodec.decoder.decode(SyncOperationPayload.self, from: operation.payload).originDeviceID) ?? "unowned"
        return "\(operation.id)|\(operation.accountKey)|\(operation.generationID)|\(owner)"
    }

    private func repairSyncOperationDuplicates(context: ModelContext, now: Date) -> Int {
        // Different operations may express successive edits to the same title.
        // Only replicas of the same immutable operation are duplicates.
        let groups = Dictionary(grouping: allOperations(context: context), by: operationIdentity)
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
        + duplicateOverflowCount(for: allShowDispositions(context: context).map { $0.mediaKey.isEmpty ? "show:\($0.tmdbID)" : $0.mediaKey })
        + duplicateOverflowCount(for: allOperations(context: context).map(operationIdentity))
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
        // Merged fields retain the oldest provenance, never the latest edit date.
        canonical.metadataCachedAt = min(canonical.metadataCachedAt, duplicate.metadataCachedAt)
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
        if record.airedAt != nil { score += 1 }
        if record.stillPath != nil { score += 1 }
        if record.overview?.isEmpty == false { score += 1 }
        if record.extrasData != nil { score += 1 }
        return score
    }

    private func mergeEpisode(_ canonical: EpisodeRecord, with duplicate: EpisodeRecord) {
        // Merged fields retain the oldest provenance, never the latest edit date.
        canonical.metadataCachedAt = min(canonical.metadataCachedAt, duplicate.metadataCachedAt)
        canonical.episodeKey = canonical.episodeKey.isEmpty ? duplicate.episodeKey : canonical.episodeKey
        if canonical.showTMDbID == 0 { canonical.showTMDbID = duplicate.showTMDbID }
        canonical.showTraktID = canonical.showTraktID ?? duplicate.showTraktID
        if canonical.tmdbID == 0 { canonical.tmdbID = duplicate.tmdbID }
        canonical.traktID = canonical.traktID ?? duplicate.traktID
        if canonical.seasonNumber == 0 { canonical.seasonNumber = duplicate.seasonNumber }
        if canonical.episodeNumber == 0 { canonical.episodeNumber = duplicate.episodeNumber }
        if canonical.name.isEmpty { canonical.name = duplicate.name }
        canonical.airDate = newest([canonical.airDate, duplicate.airDate])
        canonical.airedAt = canonical.airedAt ?? duplicate.airedAt
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
        if lhs.status == .succeeded || rhs.status == .succeeded { return lhs.status == .succeeded && rhs.status != .succeeded }
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

    // MARK: Persistence Helpers

    private func syncState(context: ModelContext) -> SyncStateRecord {
        let accountKey = accountKeyProvider() ?? "default"
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

    private func allShowDispositions(context: ModelContext) -> [ShowDispositionRecord] {
        current(rawShowDispositions(context: context), in: context, generation: \.generationID)
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

    private func rawShowDispositions(context: ModelContext) -> [ShowDispositionRecord] {
        (try? context.fetch(FetchDescriptor<ShowDispositionRecord>())) ?? []
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
        for record in rawShowDispositions(context: context)
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
            existing.airedAt = episode.firstAired ?? existing.airedAt
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
                airedAt: episode.firstAired,
                updatedAt: .now
            )
            context.insert(record)
            episodesByTMDbID[tmdbID] = record
        }
    }
}

typealias SyncRepository = SyncEngine

// MARK: - Claim Coordination

private actor SyncClaimCoordinator {
    func claimNextOperation(in persistence: Persistence,
                            deviceID: String,
                            accountKey: String,
                            claimExpiration: TimeInterval) throws -> UUID? {
        while true {
            let claimContext = persistence.makeContext()
            let claimTimestamp = Date()
            let generation = LibraryGenerationPolicy.currentGeneration(in: claimContext)
            let operations = ((try? claimContext.fetch(FetchDescriptor<SyncOperationRecord>())) ?? [])
                .filter { operation in
                    guard operation.accountKey == accountKey,
                          LibraryGenerationPolicy.belongsToCurrentGeneration(operation.generationID, current: generation),
                          let payload = try? SyncPayloadCodec.decoder.decode(SyncOperationPayload.self, from: operation.payload),
                          payload.originDeviceID == deviceID else { return false }
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

// Device-local scheduling: CloudKit replication must not suppress another device's reconciliation.
nonisolated final class HistoryReconciliationSchedule: @unchecked Sendable {
    private let defaults: UserDefaults?
    private let lock = NSLock()
    private var dates: [String: Date] = [:]
    init(defaults: UserDefaults? = nil) { self.defaults = defaults }

    func shouldReconcile(account: String, reason: SyncReason, previousPull: Date?, now: Date = .now) -> Bool {
        if reason == .userInitiated { return true }
        if reason == .localMutation { return false }
        lock.lock()
        defer { lock.unlock() }
        let key = "iWatch.fullHistorySync." + account
        let previous = dates[account] ?? defaults?.object(forKey: key) as? Date ?? previousPull
        guard let previous else { return true }
        // Establish a stable checkpoint rather than moving it on every incremental pull.
        if dates[account] == nil {
            dates[account] = previous
            defaults?.set(previous, forKey: key)
        }
        return now < previous || now.timeIntervalSince(previous) >= 86400
    }

    func recordFullSync(account: String, now: Date = .now) {
        lock.lock()
        defer { lock.unlock() }
        dates[account] = now
        defaults?.set(now, forKey: "iWatch.fullHistorySync." + account)
    }
}

nonisolated enum HistoryReconciliationError: Error, LocalizedError {
    case unconfirmed, ambiguous, waitingForAddition
    var errorDescription: String? {
        switch self {
        case .unconfirmed: return "A watched-play upload is unconfirmed. iWatch will not send it again automatically. Check Trakt before retrying."
        case .ambiguous: return "More than one watched play could match this change. Review the play in Trakt before recovering this upload."
        case .waitingForAddition: return "The watched play is still being uploaded. Its removal will wait for that upload to finish."
        }
    }
}

nonisolated enum HistoryMatchPolicy {
    static func remoteMinute(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 60) * 60)
    }

    static func samePlay(_ lhs: SyncOperationPayload, _ rhs: SyncOperationPayload) -> Bool {
        guard let a = lhs.watchedAt, let b = rhs.watchedAt else { return false }
        return lhs.mediaKind == rhs.mediaKind && lhs.tmdbID == rhs.tmdbID
            && a == b
    }
    static func matches(_ payload: SyncOperationPayload, remote: TraktHistoryItemDTO) -> Bool {
        let kind: MediaKind
        let id: Int?
        switch remote.type {
        case .movie: kind = .movie; id = remote.movie?.ids.tmdb
        case .episode: kind = .episode; id = remote.episode?.ids.tmdb
        default: return false
        }
        guard let localDate = payload.watchedAt, let remoteDate = remote.watchedAt else { return false }
        return payload.mediaKind == kind && payload.tmdbID == id
            && remoteMinute(localDate) == remoteMinute(remoteDate)
    }
}
