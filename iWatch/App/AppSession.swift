import Foundation
import Observation
import AuthenticationServices
import UIKit

// MARK: - Session State

@MainActor
@Observable
final class AppSession {
    struct TransientFeedback: Equatable, Identifiable {
        let id = UUID()
        let message: String
        let accessibilityMessage: String
        var offersUndo = false
    }

    enum CloudSyncStatus: Equatable {
        case idle
        case importing
        case imported(Date)
        case exporting
        case completed(Date)
        case unavailable(String)
        case failed(String)
        case timedOut

        var title: String {
            switch self {
            case .idle: return "Automatic"
            case .importing: return "Downloading…"
            case .imported: return "Downloaded"
            case .exporting: return "Uploading…"
            case .completed: return "Uploaded"
            case .unavailable: return "Unavailable"
            case .failed: return "Needs Attention"
            case .timedOut: return "Continuing in Background"
            }
        }

        var detail: String? {
            switch self {
            case let .completed(date), let .imported(date):
                return date.formatted(date: .abbreviated, time: .shortened)
            case let .unavailable(message), let .failed(message):
                return message
            default:
                return nil
            }
        }
    }

    enum DataResetStatus: Equatable {
        case idle
        case deletingOnDevice
        case waitingForICloud
        case completed(Date)
        case needsAttention(String)
        case failed(String)
    }

    private let trakt: TraktService
    private let syncEngine: SyncEngine
    private let configuredTraktRedirectURI: String
    private let cacheService: CacheService
    private let cloudActivityDefaults: UserDefaults?
    private let cloudExportMonitor: any CloudExportMonitoring
    private let invalidateLibrarySnapshots: @MainActor () -> Void
    private let authCoordinator = TraktAuthCoordinator()
    private var storeInvalidationTask: Task<Void, Never>?
    private var scheduledSyncTask: Task<Void, Never>?
    private var retryWakeupTask: Task<Void, Never>?
    private var followUpSync = false
    private var foregroundActive = false
    private var isDisconnectingTrakt = false
    private var backgroundContinuationTask: Task<Void, Never>?
    private var cloudSyncMonitorTask: Task<Void, Never>?
    private var transientFeedbackTask: Task<Void, Never>?
    private var syncSaveStartedAt: Date?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var pendingOAuthState: String?
    private var pendingOAuthVerifier: String?

    #if DEBUG
    var isReferencePreview = false
    #endif

    var isReadOnlyPreview: Bool {
        #if DEBUG
        isReferencePreview
        #else
        false
        #endif
    }

    var traktIsConnecting = false
    var traktLastError: String?
    var traktConnected = false
    var traktConnectionInterrupted = false
    var pendingTraktAccountKey: String?
    var isSyncing = false
    var isMaintainingSync = false
    var syncMaintenanceTitle: String?
    var isClearingCache = false
    var isErasingAllData = false
    var lastSyncAt: Date?
    var libraryRevision = 0
    var syncDiagnostics: SyncDiagnostics = .empty
    var syncProgress: SyncProgress = .idle
    var cloudSyncStatus: CloudSyncStatus = .idle
    var lastCloudImportAt: Date? {
        didSet { cloudActivityDefaults?.set(lastCloudImportAt, forKey: "cloudLastImportAt") }
    }
    var lastCloudExportAt: Date? {
        didSet { cloudActivityDefaults?.set(lastCloudExportAt, forKey: "cloudLastExportAt") }
    }
    var lastCloudActivityAt: Date? {
        [lastCloudImportAt, lastCloudExportAt].compactMap { $0 }.max()
    }
    var syncMaintenanceMessage: String?
    var cacheMaintenanceMessage: String?
    var dataResetStatus: DataResetStatus = .idle
    var transientFeedback: TransientFeedback?

    init(trakt: TraktService,
         syncEngine: SyncEngine,
         traktRedirectURI: String,
         cacheService: CacheService,
         cloudExportMonitor: any CloudExportMonitoring,
         cloudActivityDefaults: UserDefaults? = nil,
         invalidateLibrarySnapshots: @escaping @MainActor () -> Void = {}) {
        self.trakt = trakt
        self.syncEngine = syncEngine
        self.configuredTraktRedirectURI = traktRedirectURI
        self.cacheService = cacheService
        self.cloudActivityDefaults = cloudActivityDefaults
        self.lastCloudImportAt = cloudActivityDefaults?.object(forKey: "cloudLastImportAt") as? Date
        self.lastCloudExportAt = cloudActivityDefaults?.object(forKey: "cloudLastExportAt") as? Date
        self.cloudExportMonitor = cloudExportMonitor
        self.invalidateLibrarySnapshots = invalidateLibrarySnapshots
        cloudExportMonitor.observeActivity { [weak self] activity in
            guard let self else { return }
            switch activity {
            case .accountChanged:
                self.lastCloudImportAt = nil
                self.lastCloudExportAt = nil
                self.cloudSyncStatus = .idle
            case .importing: self.cloudSyncStatus = .importing
            case let .imported(date):
                self.lastCloudImportAt = max(self.lastCloudImportAt ?? date, date)
                self.cloudSyncStatus = .imported(date)
                self.scheduleLibraryInvalidation()
            case .exporting: self.cloudSyncStatus = .exporting
            case let .exported(date):
                self.lastCloudExportAt = max(self.lastCloudExportAt ?? date, date)
                self.cloudSyncStatus = .completed(date)
            case let .failed(message): self.cloudSyncStatus = .failed(message)
            }
        }

        if DataResetReceiptStore.pendingResetAt != nil {
            dataResetStatus = .needsAttention(
                "The data was removed from this device, but the iCloud update still needs confirmation."
            )
        }

        Task { [weak self] in
            guard let self else { return }
            _ = await self.refreshAuthState()
            await self.refreshSyncDiagnostics()
        }
    }

    var traktRedirectURI: String {
        configuredTraktRedirectURI
    }

    func showMovieWatchSuccess(title: String, isRewatch: Bool) {
        let message = isRewatch ? "Play added • \(title)" : title
        let accessibilityMessage = isRewatch
            ? "Another play added for \(title)"
            : "\(title) marked watched"
        showWatchSuccess(message, accessibilityMessage: accessibilityMessage)
    }

    @ObservationIgnored private var feedbackUndo: (@MainActor () async -> Void)?

    func undoWatchFeedback() async {
        let action = feedbackUndo
        feedbackUndo = nil
        transientFeedbackTask?.cancel()
        transientFeedback = nil
        await action?()
    }

    func showEpisodeWatchSuccess(showTitle: String, season: Int, episode: Int,
                                 undo: (@MainActor () async -> Void)? = nil) {
        showWatchSuccess(
            "S\(season) E\(episode) Watched",
            accessibilityMessage: "\(showTitle), season \(season) episode \(episode), marked watched",
            undo: undo
        )
    }

    private func showWatchSuccess(_ message: String, accessibilityMessage: String,
                                  undo: (@MainActor () async -> Void)? = nil) {
        let accountKey = TraktLinkStore.activeAccountKey
        feedbackUndo = {
            guard TraktLinkStore.activeAccountKey == accountKey else { return }
            await undo?()
        }
        transientFeedbackTask?.cancel()

        let feedback = TransientFeedback(
            message: message,
            accessibilityMessage: accessibilityMessage,
            offersUndo: undo != nil
        )
        transientFeedback = feedback
        Haptics.notification(.success)
        UIAccessibility.post(notification: .announcement, argument: accessibilityMessage)

        transientFeedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(undo == nil ? 3 : 6))
            guard !Task.isCancelled, self?.transientFeedback?.id == feedback.id else { return }
            self?.transientFeedback = nil
            self?.feedbackUndo = nil
        }
    }

    // MARK: Trakt Connection

    func startTraktOAuth() {
        guard !traktIsConnecting else { return }
        guard !isSyncing, !isDisconnectingTrakt, !isMaintainingSync else {
            traktLastError = "Wait for the current Trakt operation to finish before connecting an account."
            return
        }
        do {
            let state = OAuthStateGenerator.make()
            let authRequest = try trakt.authorizationRequest(redirectURI: traktRedirectURI, state: state)
            _ = try callbackScheme()
            pendingOAuthState = authRequest.state
            pendingOAuthVerifier = authRequest.codeVerifier
            traktLastError = nil
            traktIsConnecting = true

            authCoordinator.start(authURL: authRequest.url, callbackURL: URL(string: traktRedirectURI)!, prefersEphemeral: true) { [weak self] callbackURL, error in
                guard let self else { return }
                if let error {
                    Task { @MainActor in
                        guard self.pendingOAuthState == authRequest.state else { return }
                        self.traktIsConnecting = false
                        self.pendingOAuthState = nil
                        self.pendingOAuthVerifier = nil
                        if (error as NSError).code != ASWebAuthenticationSessionError.canceledLogin.rawValue {
                            self.traktLastError = error.localizedDescription
                        }
                    }
                    return
                }

                guard let callbackURL else {
                    Task { @MainActor in
                        guard self.pendingOAuthState == authRequest.state else { return }
                        self.traktIsConnecting = false
                        self.pendingOAuthState = nil
                        self.pendingOAuthVerifier = nil
                        self.traktLastError = TraktAuthError.missingAuthorizationCode.errorDescription
                    }
                    return
                }

                Task { @MainActor [weak self] in
                    guard let self, self.pendingOAuthState == authRequest.state else { return }
                    await self.completeTraktOAuth(callbackURL: callbackURL)
                }
            }
        } catch {
            pendingOAuthState = nil
            pendingOAuthVerifier = nil
            traktIsConnecting = false
            traktLastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func runSync(reason: SyncReason = .userInitiated) async {
        guard !isMaintainingSync else { return }
        await performSync(reason: reason)
    }

    private func performSync(reason: SyncReason, allowMaintenance: Bool = false, historyRetry: SyncEngine.HistoryRetry? = nil) async {
        guard !isErasingAllData else { return }
        guard pendingTraktAccountKey == nil, !traktIsConnecting, !isDisconnectingTrakt else { return }
        guard let expectedAccount = TraktLinkStore.activeAccountKey else { return }
        if isSyncing {
            followUpSync = true
            return
        }
        retryWakeupTask?.cancel()
        isSyncing = true
        defer {
            isSyncing = false
            endBackgroundTaskIfNeeded()
            if TraktLinkStore.activeAccountKey == expectedAccount {
                if followUpSync {
                    followUpSync = false
                    scheduleDebouncedSync(reason: .localMutation)
                } else {
                    scheduleRetryWakeup(for: expectedAccount)
                }
            }
        }
        guard await refreshAuthState(), !Task.isCancelled, !isErasingAllData,
              !isMaintainingSync || allowMaintenance,
              pendingTraktAccountKey == nil, !traktIsConnecting, !isDisconnectingTrakt,
              TraktLinkStore.activeAccountKey == expectedAccount else { return }
        let syncStartedAt = Date()
        syncSaveStartedAt = nil
        if !isMaintainingSync { syncMaintenanceMessage = nil }
        let succeeded = await syncEngine.run(reason: reason, historyRetry: historyRetry, libraryChanged: { [weak self] in
            self?.scheduleLibraryInvalidation()
        }) { [weak self] progress in
            guard TraktLinkStore.activeAccountKey == expectedAccount else { return }
            self?.syncProgress = progress
            if case .saving = progress {
                self?.syncSaveStartedAt = Date()
            }
        }
        guard TraktLinkStore.activeAccountKey == expectedAccount else { return }
        await refreshSyncDiagnostics()
        guard TraktLinkStore.activeAccountKey == expectedAccount else { return }
        guard succeeded else {
            _ = await refreshAuthState()
            guard TraktLinkStore.activeAccountKey == expectedAccount else { return }
            traktLastError = syncDiagnostics.lastErrorDescription ?? "Sync failed."
            return
        }

        traktLastError = nil
        lastSyncAt = Date()
        monitorCloudExport(startingAfter: syncSaveStartedAt ?? syncStartedAt)
        syncSaveStartedAt = nil
        BackgroundRefresh.scheduleAppRefresh()
    }

    func logoutTrakt() {
        guard !isDisconnectingTrakt, !isMaintainingSync else { return }
        isDisconnectingTrakt = true
        followUpSync = false
        retryWakeupTask?.cancel()
        scheduledSyncTask?.cancel()
        backgroundContinuationTask?.cancel()
        endBackgroundTaskIfNeeded()
        BackgroundRefresh.cancelScheduledRefresh()
        pendingOAuthState = nil
        pendingOAuthVerifier = nil
        pendingTraktAccountKey = nil
        traktIsConnecting = false
        TraktLinkStore.clear()

        Task { [weak self] in
            guard let self else { return }
            await self.trakt.clearAuth()
            await MainActor.run {
                self.isDisconnectingTrakt = false
                self.traktConnected = false
                self.lastSyncAt = nil
                self.traktConnectionInterrupted = false
                self.traktLastError = nil
                self.syncMaintenanceMessage = nil
                self.syncDiagnostics = .empty
                self.syncProgress = .idle
            }
        }
    }

    // MARK: Data Maintenance

    func clearCache() async {
        guard !isClearingCache else { return }
        isClearingCache = true
        cacheMaintenanceMessage = nil
        defer { isClearingCache = false }

        await clearOnDeviceCaches(cacheService: cacheService)
        cacheMaintenanceMessage = "Cleared local image and network caches."
    }

    func eraseAllAppData() async {
        guard !isMaintainingSync, !isErasingAllData else { return }

        isErasingAllData = true
        dataResetStatus = .deletingOnDevice
        await syncEngine.beginDataReset()
        cacheMaintenanceMessage = nil
        syncMaintenanceMessage = nil
        scheduledSyncTask?.cancel()
        backgroundContinuationTask?.cancel()
        cloudSyncMonitorTask?.cancel()
        endBackgroundTaskIfNeeded()
        BackgroundRefresh.cancelScheduledRefresh()
        pendingOAuthState = nil
        pendingOAuthVerifier = nil
        pendingTraktAccountKey = nil
        traktIsConnecting = false
        isSyncing = false

        defer { isErasingAllData = false }

        await trakt.clearAuth()
        TraktLinkStore.clear()

        do {
            let resetAt = try await syncEngine.eraseAllAppData()
            DataResetReceiptStore.markPending(at: resetAt)
            clearStoredPreferences()
            await clearOnDeviceCaches(cacheService: cacheService)

            traktConnected = false
            traktLastError = nil
            lastSyncAt = nil
            syncDiagnostics = .empty
            syncProgress = .idle
            cloudSyncStatus = .idle
            lastCloudImportAt = nil
            lastCloudExportAt = nil
            syncMaintenanceMessage = "All app data was erased. Trakt was disconnected on this device."
            cacheMaintenanceMessage = "Cleared local image and network caches."
            markLibraryUpdated()

            await confirmCloudResetExport(startingAfter: resetAt)
        } catch {
            traktLastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            dataResetStatus = .failed(traktLastError ?? "The reset couldn’t be completed.")
            await refreshSyncDiagnostics()
        }
        await syncEngine.endDataReset()
    }

    func retryCloudResetConfirmation() async {
        guard !isMaintainingSync, !isErasingAllData else { return }
        isErasingAllData = true
        dataResetStatus = .waitingForICloud
        await syncEngine.beginDataReset()
        defer { isErasingAllData = false }

        do {
            let resetAt = try await syncEngine.requestCloudResetConfirmation()
            DataResetReceiptStore.markPending(at: resetAt)
            await confirmCloudResetExport(startingAfter: resetAt)
        } catch {
            dataResetStatus = .needsAttention(error.localizedDescription)
        }
        await syncEngine.endDataReset()
    }

    private func confirmCloudResetExport(startingAfter resetAt: Date) async {
        dataResetStatus = .waitingForICloud
        let confirmation = await cloudExportMonitor.waitForExport(
            startingAfter: resetAt,
            timeout: .seconds(30)
        )
        switch confirmation {
        case let .completed(date):
            DataResetReceiptStore.markConfirmed()
            dataResetStatus = .completed(date)
        case let .unavailable(message), let .failed(message):
            dataResetStatus = .needsAttention(message)
        case .timedOut:
            dataResetStatus = .needsAttention(
                "The data was removed from this device, but iWatch couldn’t confirm the iCloud update yet. Keep iWatch installed and online."
            )
        }
    }

    // MARK: App Lifecycle

    func scheduleLibraryInvalidation() {
        storeInvalidationTask?.cancel()
        storeInvalidationTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            self?.markLibraryUpdated()
        }
    }

    func markLibraryUpdated(syncIfConnected: Bool = false) {
        invalidateLibrarySnapshots()
        libraryRevision &+= 1

        guard syncIfConnected else { return }

        scheduleDebouncedSync(reason: .localMutation)
    }

    func appDidBecomeActive() {
        foregroundActive = true
        backgroundContinuationTask?.cancel()
        endBackgroundTaskIfNeeded()

        Task { [weak self] in
            guard let self else { return }
            guard await self.refreshAuthState() else { return }
            BackgroundRefresh.scheduleAppRefresh()

            let shouldRefresh = await self.syncEngine.shouldRefreshOnForeground(
                maxStaleness: BackgroundRefresh.foregroundStalenessInterval
            )
            if shouldRefresh {
                await self.runSync(reason: .foreground)
            }
        }
    }

    func appDidEnterBackground() {
        foregroundActive = false
        retryWakeupTask?.cancel()
        backgroundContinuationTask?.cancel()

        backgroundContinuationTask = Task { [weak self] in
            guard let self else { return }

            self.scheduledSyncTask?.cancel()

            guard await self.refreshAuthState() else { return }
            BackgroundRefresh.scheduleAppRefresh()

            let hasPendingOperations = await self.syncEngine.hasPendingOperations()
            let shouldContinue = self.isSyncing || hasPendingOperations
            guard shouldContinue else { return }

            self.beginBackgroundTaskIfNeeded()
            if !self.isSyncing {
                await self.runSync(reason: .background)
            }
        }
    }

    func handleBackgroundRefresh() async {
        guard BackgroundRefresh.isAvailableInCurrentProcess else { return }
        guard await refreshAuthState() else { return }

        BackgroundRefresh.scheduleAppRefresh()
        await runSync(reason: .background)
    }

    func refreshSyncDiagnostics() async {
        guard !isReadOnlyPreview else { return }
        let account = TraktLinkStore.activeAccountKey
        let diagnostics = await syncEngine.diagnostics()
        guard TraktLinkStore.activeAccountKey == account else { return }
        syncDiagnostics = diagnostics
        #if DEBUG
        applySyncSettingsFixtureIfRequested()
        #endif
        if !isSyncing, syncProgress == .idle, syncDiagnostics.initialBaselineComplete {
            syncProgress = .complete
        }
    }

    private func monitorCloudExport(startingAfter date: Date) {
        cloudSyncMonitorTask?.cancel()
        cloudSyncStatus = .exporting
        cloudSyncMonitorTask = Task { [weak self] in
            guard let self else { return }
            let confirmation = await self.cloudExportMonitor.waitForExport(
                startingAfter: date,
                timeout: .seconds(60)
            )
            guard !Task.isCancelled else { return }
            switch confirmation {
            case let .completed(completedAt):
                self.lastCloudExportAt = max(self.lastCloudExportAt ?? completedAt, completedAt)
                self.cloudSyncStatus = .completed(completedAt)
            case let .unavailable(message):
                self.cloudSyncStatus = .unavailable(message)
            case let .failed(message):
                self.cloudSyncStatus = .failed(message)
            case .timedOut:
                self.cloudSyncStatus = .timedOut
            }
        }
    }

    // MARK: Sync Maintenance

    func importTraktLibrary() async {
        guard let account = pendingTraktAccountKey else { return }
        await replaceLibraryFromTrakt(account: account, linking: true)
    }

    func uploadLocalLibrary() async {
        guard !isSyncing, !isMaintainingSync, !isErasingAllData else { return }
        isMaintainingSync = true
        syncMaintenanceTitle = "Preparing Uploads…"
        syncMaintenanceMessage = nil
        defer { isMaintainingSync = false; syncMaintenanceTitle = nil }
        guard let accountKey = pendingTraktAccountKey else { return }
        do {
            try await syncEngine.assignUnlinkedOperations(to: accountKey)
            TraktLinkStore.activeAccountKey = accountKey
            pendingTraktAccountKey = nil
            await performSync(reason: .userInitiated, allowMaintenance: true)
        } catch {
            traktLastError = error.localizedDescription
        }
    }

    func syncTraktNow(historyRetry: SyncEngine.HistoryRetry? = nil) async -> SyncEngine.HistoryRetry? {
        guard !syncActionsUnavailable, let account = TraktLinkStore.activeAccountKey,
              historyRetry == nil || historyRetry?.account == account else { return nil }
        isMaintainingSync = true
        syncMaintenanceTitle = historyRetry == nil ? "Syncing…" : "Retrying Upload…"
        defer { isMaintainingSync = false; syncMaintenanceTitle = nil }
        do {
            try await syncEngine.prepareManualSync(for: account, retryFailedChanges: historyRetry == nil)
            guard TraktLinkStore.activeAccountKey == account else { return nil }
            let hasQueuedWork = syncDiagnostics.hasPendingWork || syncDiagnostics.deadletterOperationCount > 0
            let reason: SyncReason = hasQueuedWork || historyRetry != nil ? .pendingChanges : .userInitiated
            await performSync(reason: reason, allowMaintenance: true, historyRetry: historyRetry)
            guard historyRetry == nil, traktConnected else { return nil }
            return await syncEngine.historyRetryOffer(for: account)
        } catch {
            traktLastError = error.localizedDescription
            await refreshSyncDiagnostics()
            return nil
        }
    }

    func recoverPendingUploads() async {
        guard !isSyncing, !isMaintainingSync, !isErasingAllData else { return }
        isMaintainingSync = true
        syncMaintenanceTitle = "Moving Uploads…"
        syncMaintenanceMessage = nil
        defer { isMaintainingSync = false; syncMaintenanceTitle = nil }
        do {
            let count = try await syncEngine.recoverPendingUploads()
            syncMaintenanceMessage = "Recovered \(count) pending uploads on this device."
            await performSync(reason: .localMutation, allowMaintenance: true)
        } catch { traktLastError = error.localizedDescription }
        await refreshSyncDiagnostics()
    }

    func repairLocalSyncData() async {
        guard !isSyncing, !isMaintainingSync, !isErasingAllData else { return }
        isMaintainingSync = true
        syncMaintenanceTitle = "Checking Library…"
        syncMaintenanceMessage = nil
        defer { isMaintainingSync = false; syncMaintenanceTitle = nil }
        do {
            let summary = try await syncEngine.repairIntegrity()
            await refreshSyncDiagnostics()
            syncMaintenanceMessage = summary.totalChanges == 0
                ? "No local sync integrity issues were found."
                : "Repaired \(summary.totalChanges) local sync issue\(summary.totalChanges == 1 ? "" : "s")."
            markLibraryUpdated()
        } catch {
            traktLastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await refreshSyncDiagnostics()
        }
    }

    func resetLocalTraktSyncCache() async {
        guard pendingTraktAccountKey == nil, let account = TraktLinkStore.activeAccountKey else { return }
        await replaceLibraryFromTrakt(account: account, linking: false)
    }

    private func replaceLibraryFromTrakt(account: String, linking: Bool) async {
        guard !isSyncing, !isMaintainingSync, !isErasingAllData,
              !traktIsConnecting, !isDisconnectingTrakt else { return }
        isMaintainingSync = true
        syncMaintenanceTitle = linking ? "Importing Library…" : "Rebuilding Library…"
        syncMaintenanceMessage = nil
        defer { isMaintainingSync = false; syncMaintenanceTitle = nil }

        await syncEngine.beginDataReset()
        do {
            let saveStartedAt = try await syncEngine.replaceLibraryFromTrakt(account: account)
            if linking {
                TraktLinkStore.activeAccountKey = account
                pendingTraktAccountKey = nil
            }
            lastSyncAt = Date()
            traktLastError = nil
            syncProgress = .complete
            syncMaintenanceMessage = "The library was rebuilt from Trakt."
            markLibraryUpdated()
            monitorCloudExport(startingAfter: saveStartedAt)
            BackgroundRefresh.scheduleAppRefresh()
        } catch {
            traktLastError = UserFacingError.message(for: error, context: .action)
        }
        await syncEngine.endDataReset()
        await refreshSyncDiagnostics()
    }

    @discardableResult
    // MARK: Authentication State

    func refreshAuthState() async -> Bool {
        guard !traktIsConnecting, !isDisconnectingTrakt else { return false }
        if isReadOnlyPreview { return traktConnected }
        do {
            let status = try await trakt.sessionStatus()
            guard !traktIsConnecting, !isDisconnectingTrakt else { return false }
            traktConnectionInterrupted = false
            switch status {
            case .connected:
                traktConnected = true
                guard TraktLinkStore.activeAccountKey != nil else {
                    BackgroundRefresh.cancelScheduledRefresh()
                    if pendingTraktAccountKey == nil {
                        do {
                            let account = try await trakt.authenticatedAccount().syncKey
                            guard !traktIsConnecting, !isDisconnectingTrakt,
                                  TraktLinkStore.activeAccountKey == nil, pendingTraktAccountKey == nil else { return false }
                            pendingTraktAccountKey = account
                            traktLastError = nil
                            syncMaintenanceMessage = "Choose how to link this Trakt account before syncing."
                        } catch {
                            traktLastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        }
                    }
                    return false
                }
                BackgroundRefresh.scheduleAppRefresh()
                return true
            case .disconnected:
                traktConnected = false
                BackgroundRefresh.cancelScheduledRefresh()
                return false
            case let .reauthorizationRequired(message):
                traktConnected = false
                traktIsConnecting = false
                pendingOAuthState = nil
                pendingOAuthVerifier = nil
                BackgroundRefresh.cancelScheduledRefresh()
                traktLastError = message
                return false
            }
        } catch {
            let hasToken = await trakt.currentToken() != nil
            guard !traktIsConnecting, !isDisconnectingTrakt else { return false }
            traktConnected = hasToken
            traktConnectionInterrupted = error is URLError
            BackgroundRefresh.cancelScheduledRefresh()
            traktLastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    // MARK: Helpers

    private func scheduleDebouncedSync(reason: SyncReason) {
        scheduledSyncTask?.cancel()

        scheduledSyncTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            // The debounce owns the timer. A later edit must not cancel a run already draining.
            self.scheduledSyncTask = nil
            await self.runSync(reason: reason)
        }
    }

    private func scheduleRetryWakeup(for account: String) {
        retryWakeupTask?.cancel()
        guard foregroundActive else { return }
        retryWakeupTask = Task { [weak self] in
            guard let self, let retryAt = await self.syncEngine.nextRetryDate(for: account) else { return }
            // An overdue row can survive an offline pull. Avoid an immediate retry loop.
            let remaining = retryAt.timeIntervalSinceNow
            do { try await Task.sleep(for: .seconds(remaining > 0 ? remaining : 30)) } catch { return }
            guard !Task.isCancelled, self.foregroundActive, TraktLinkStore.activeAccountKey == account else { return }
            self.retryWakeupTask = nil
            await self.runSync(reason: .localMutation)
        }
    }

    private func beginBackgroundTaskIfNeeded() {
        guard BackgroundRefresh.isAvailableInCurrentProcess else { return }
        guard backgroundTaskID == .invalid else { return }

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "iWatchSyncContinuation") { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduledSyncTask?.cancel()
                self?.backgroundContinuationTask?.cancel()
                self?.endBackgroundTaskIfNeeded()
            }
        }
    }

    private func endBackgroundTaskIfNeeded() {
        guard backgroundTaskID != .invalid else { return }

        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func callbackScheme() throws -> String {
        guard let scheme = URL(string: traktRedirectURI)?.scheme, !scheme.isEmpty else {
            throw TraktAuthError.invalidRedirectURI
        }
        if scheme == "https", let url = URL(string: traktRedirectURI),
           url.host == "tylerkeegan.com", url.path == "/iwatch/oauth/trakt" { return scheme }
        guard isRegisteredURLScheme(scheme) else {
            throw TraktAuthError.redirectSchemeNotRegistered(scheme: scheme)
        }
        return scheme
    }

    private func isRegisteredURLScheme(_ scheme: String) -> Bool {
        guard let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
            return false
        }

        return urlTypes
            .compactMap { $0["CFBundleURLSchemes"] as? [String] }
            .flatMap { $0 }
            .contains { $0.caseInsensitiveCompare(scheme) == .orderedSame }
    }

    private func completeTraktOAuth(callbackURL: URL) async {
        guard let state = pendingOAuthState, let verifier = pendingOAuthVerifier else { return }
        var exchangedToken = false
        defer {
            if pendingOAuthState == state {
                traktIsConnecting = false
                pendingOAuthState = nil
                pendingOAuthVerifier = nil
            }
        }

        do {
            let code = try trakt.authorizationCode(from: callbackURL, expectedState: state)
            // A replacement token must go through account setup even if the app exits mid-OAuth.
            TraktLinkStore.clear()
            _ = try await trakt.exchangeCodeForToken(code: code, redirectURI: traktRedirectURI, codeVerifier: verifier)
            exchangedToken = true
            let account = try await trakt.authenticatedAccount()
            guard pendingOAuthState == state else { return }
            pendingTraktAccountKey = account.syncKey
            traktConnected = true
            traktLastError = nil
            syncMaintenanceMessage = "Choose how to link this Trakt account before syncing."
        } catch {
            guard pendingOAuthState == state else { return }
            if exchangedToken {
                await trakt.clearAuth()
                guard pendingOAuthState == state else { return }
            }
            traktConnected = false
            pendingTraktAccountKey = nil
            BackgroundRefresh.cancelScheduledRefresh()
            traktLastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await refreshSyncDiagnostics()
        }
    }

    private func clearStoredPreferences() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "defaultTab")
        defaults.removeObject(forKey: "hideEndedShows")
        defaults.removeObject(forKey: "appTheme")
    }
}
