import Foundation
import Observation
import AuthenticationServices
import UIKit

@MainActor
@Observable
final class AppSession {
    enum CloudSyncStatus: Equatable {
        case idle
        case exporting
        case completed(Date)
        case unavailable(String)
        case failed(String)
        case timedOut

        var title: String {
            switch self {
            case .idle: return "Waiting"
            case .exporting: return "Uploading…"
            case .completed: return "Uploaded"
            case .unavailable: return "Unavailable"
            case .failed: return "Needs Attention"
            case .timedOut: return "Continuing in Background"
            }
        }

        var detail: String? {
            switch self {
            case let .completed(date):
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
    private let cloudExportMonitor: any CloudExportMonitoring
    private let authCoordinator = TraktAuthCoordinator()
    private var scheduledSyncTask: Task<Void, Never>?
    private var backgroundContinuationTask: Task<Void, Never>?
    private var cloudSyncMonitorTask: Task<Void, Never>?
    private var syncSaveStartedAt: Date?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var pendingOAuthState: String?

    var traktIsConnecting = false
    var traktLastError: String?
    var traktConnected = false
    var pendingTraktAccountKey: String?
    var isSyncing = false
    var isClearingCache = false
    var isErasingAllData = false
    var lastSyncAt: Date?
    var libraryRevision = 0
    var syncDiagnostics: SyncDiagnostics = .empty
    var syncProgress: SyncProgress = .idle
    var cloudSyncStatus: CloudSyncStatus = .idle
    var syncMaintenanceMessage: String?
    var cacheMaintenanceMessage: String?
    var dataResetStatus: DataResetStatus = .idle

    init(trakt: TraktService,
         syncEngine: SyncEngine,
         traktRedirectURI: String,
         cacheService: CacheService,
         cloudExportMonitor: any CloudExportMonitoring) {
        self.trakt = trakt
        self.syncEngine = syncEngine
        self.configuredTraktRedirectURI = traktRedirectURI
        self.cacheService = cacheService
        self.cloudExportMonitor = cloudExportMonitor

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

    func startTraktOAuth() {
        do {
            let state = OAuthStateGenerator.make()
            let authRequest = try trakt.authorizationRequest(redirectURI: traktRedirectURI, state: state)
            let callbackScheme = try callbackScheme()
            pendingOAuthState = authRequest.state
            traktLastError = nil
            traktIsConnecting = true

            authCoordinator.start(authURL: authRequest.url, callbackScheme: callbackScheme, prefersEphemeral: true) { [weak self] callbackURL, error in
                guard let self else { return }
                if let error {
                    Task { @MainActor in
                        self.traktIsConnecting = false
                        self.pendingOAuthState = nil
                        if (error as NSError).code != ASWebAuthenticationSessionError.canceledLogin.rawValue {
                            self.traktLastError = error.localizedDescription
                        }
                    }
                    return
                }

                guard let callbackURL else {
                    Task { @MainActor in
                        self.traktIsConnecting = false
                        self.pendingOAuthState = nil
                        self.traktLastError = TraktAuthError.missingAuthorizationCode.errorDescription
                    }
                    return
                }

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.completeTraktOAuth(callbackURL: callbackURL)
                }
            }
        } catch {
            pendingOAuthState = nil
            traktIsConnecting = false
            traktLastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func runSync(reason: SyncReason = .userInitiated) async {
        guard !isErasingAllData else { return }
        guard pendingTraktAccountKey == nil else { return }
        guard TraktLinkStore.activeAccountKey != nil else { return }
        guard await refreshAuthState(), !isSyncing else { return }
        isSyncing = true
        let syncStartedAt = Date()
        syncSaveStartedAt = nil
        syncMaintenanceMessage = nil
        defer {
            isSyncing = false
            endBackgroundTaskIfNeeded()
        }

        let succeeded = await syncEngine.run(reason: reason) { [weak self] progress in
            self?.syncProgress = progress
            if case .saving = progress {
                self?.syncSaveStartedAt = Date()
            }
        }
        await refreshSyncDiagnostics()
        guard succeeded else {
            _ = await refreshAuthState()
            traktLastError = syncDiagnostics.lastErrorDescription ?? "Sync failed."
            return
        }

        lastSyncAt = Date()
        monitorCloudExport(startingAfter: syncSaveStartedAt ?? syncStartedAt)
        syncSaveStartedAt = nil
        BackgroundRefresh.scheduleAppRefresh()
        markLibraryUpdated()
    }

    func logoutTrakt() {
        scheduledSyncTask?.cancel()
        backgroundContinuationTask?.cancel()
        cloudSyncMonitorTask?.cancel()
        endBackgroundTaskIfNeeded()
        BackgroundRefresh.cancelScheduledRefresh()
        pendingOAuthState = nil
        pendingTraktAccountKey = nil
        traktIsConnecting = false
        TraktLinkStore.clear()

        Task { [weak self] in
            guard let self else { return }
            await self.trakt.clearAuth()
            await MainActor.run {
                self.traktConnected = false
                self.traktLastError = nil
                self.syncMaintenanceMessage = nil
                self.syncDiagnostics = .empty
                self.syncProgress = .idle
                self.cloudSyncStatus = .idle
            }
        }
    }

    func clearCache() async {
        guard !isClearingCache else { return }
        isClearingCache = true
        cacheMaintenanceMessage = nil
        defer { isClearingCache = false }

        await clearOnDeviceCaches(cacheService: cacheService)
        cacheMaintenanceMessage = "Cleared local image and network caches."
    }

    func eraseAllAppData() async {
        guard !isErasingAllData else { return }

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
        guard !isErasingAllData else { return }
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

    func markLibraryUpdated(syncIfConnected: Bool = false) {
        libraryRevision &+= 1

        guard syncIfConnected else { return }

        scheduleDebouncedSync(reason: .userInitiated)
    }

    func appDidBecomeActive() {
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
        syncDiagnostics = await syncEngine.diagnostics()
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

    func importTraktLibrary() async {
        guard let accountKey = pendingTraktAccountKey else { return }
        await syncEngine.beginDataReset()
        var shouldSync = false
        do {
            try await syncEngine.resetLocalTraktSyncCache()
            TraktLinkStore.activeAccountKey = accountKey
            pendingTraktAccountKey = nil
            shouldSync = true
        } catch {
            traktLastError = error.localizedDescription
        }
        await syncEngine.endDataReset()
        if shouldSync {
            await runSync(reason: .userInitiated)
        }
    }

    func uploadLocalLibrary() async {
        guard let accountKey = pendingTraktAccountKey else { return }
        do {
            try await syncEngine.assignUnlinkedOperations(to: accountKey)
            TraktLinkStore.activeAccountKey = accountKey
            pendingTraktAccountKey = nil
            await runSync(reason: .userInitiated)
        } catch {
            traktLastError = error.localizedDescription
        }
    }

    func retryFailedSyncOperations() async {
        do {
            let retried = try await syncEngine.retryDeadletterOperations()
            await refreshSyncDiagnostics()

            if retried == 0 {
                syncMaintenanceMessage = "There were no failed sync operations to retry."
                return
            }

            syncMaintenanceMessage = "Queued \(retried) failed sync operation\(retried == 1 ? "" : "s") for retry."
            await runSync(reason: .userInitiated)
        } catch {
            traktLastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await refreshSyncDiagnostics()
        }
    }

    func repairLocalSyncData() async {
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
        await syncEngine.beginDataReset()
        var shouldSync = false
        do {
            try await syncEngine.resetLocalTraktSyncCache()
            lastSyncAt = nil
            syncMaintenanceMessage = "Local Trakt sync data was reset. Rebuilding from Trakt now."
            markLibraryUpdated()
            await refreshSyncDiagnostics()

            shouldSync = await refreshAuthState()
        } catch {
            traktLastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await refreshSyncDiagnostics()
        }
        await syncEngine.endDataReset()
        if shouldSync {
            await runSync(reason: .userInitiated)
        }
    }

    @discardableResult
    func refreshAuthState() async -> Bool {
        do {
            let status = try await trakt.sessionStatus()
            switch status {
            case .connected:
                traktConnected = true
                guard TraktLinkStore.activeAccountKey != nil else {
                    BackgroundRefresh.cancelScheduledRefresh()
                    if pendingTraktAccountKey == nil {
                        do {
                            pendingTraktAccountKey = try await trakt.authenticatedAccount().syncKey
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
                BackgroundRefresh.cancelScheduledRefresh()
                traktLastError = message
                return false
            }
        } catch {
            traktConnected = false
            BackgroundRefresh.cancelScheduledRefresh()
            traktLastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

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
            guard await self.refreshAuthState() else { return }

            await self.runSync(reason: reason)
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
        var exchangedToken = false
        defer {
            traktIsConnecting = false
            pendingOAuthState = nil
        }

        do {
            guard let pendingOAuthState else {
                throw TraktAuthError.stateMismatch
            }

            let code = try trakt.authorizationCode(from: callbackURL, expectedState: pendingOAuthState)
            _ = try await trakt.exchangeCodeForToken(code: code, redirectURI: traktRedirectURI)
            exchangedToken = true
            pendingTraktAccountKey = try await trakt.authenticatedAccount().syncKey
            traktConnected = true
            traktLastError = nil
            syncMaintenanceMessage = "Choose how to link this Trakt account before syncing."
        } catch {
            if exchangedToken {
                await trakt.clearAuth()
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
