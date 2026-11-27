import Foundation
import Observation
import UIKit
import UserNotifications

enum ReleaseNotificationPreferences {
    static let episodesEnabledKey = "releaseNotifications.episodesEnabled"
    static let moviesEnabledKey = "releaseNotifications.moviesEnabled"
    static let timingKey = "releaseNotificationTiming"

    static var enabled: Bool { episodesEnabled || moviesEnabled }
    static var episodesEnabled: Bool { UserDefaults.standard.bool(forKey: episodesEnabledKey) }
    static var moviesEnabled: Bool { UserDefaults.standard.bool(forKey: moviesEnabledKey) }

    static func migrateLegacyPreferences(in defaults: UserDefaults = .standard) {
        let legacyEnabled = defaults.bool(forKey: "releaseNotificationsEnabled")
        for (key, legacyKey) in [
            (episodesEnabledKey, "episodeReleaseNotificationsEnabled"),
            (moviesEnabledKey, "movieReleaseNotificationsEnabled")
        ] where defaults.object(forKey: key) == nil {
            let categoryEnabled = defaults.object(forKey: legacyKey) as? Bool ?? true
            defaults.set(legacyEnabled && categoryEnabled, forKey: key)
        }
    }

    static var timing: ReleaseNotificationTiming {
        UserDefaults.standard.string(forKey: timingKey)
            .flatMap(ReleaseNotificationTiming.init(rawValue:)) ?? .atRelease
    }
}

@MainActor
@Observable
final class ReleaseNotificationCoordinator {
    private static let managedPrefix = "release."
    private let repository: LibraryRepository
    private let center: UNUserNotificationCenter
    private let readAuthorization: @MainActor () async -> UNAuthorizationStatus
    private let requestAuthorization: @MainActor () async throws -> Bool

    private var reconciliationTask: Task<Void, Never>?
    private var needsReconciliation = false

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var scheduledCount = 0

    init(
        repository: LibraryRepository,
        center: UNUserNotificationCenter = .current(),
        readAuthorization: (@MainActor () async -> UNAuthorizationStatus)? = nil,
        requestAuthorization: (@MainActor () async throws -> Bool)? = nil
    ) {
        self.repository = repository
        self.center = center
        self.readAuthorization = readAuthorization ?? { await center.notificationSettings().authorizationStatus }
        self.requestAuthorization = requestAuthorization ?? { try await center.requestAuthorization(options: [.alert, .badge, .sound]) }
    }

    func refreshStatus() async {
        authorizationStatus = await readAuthorization()
        let pending = await center.pendingNotificationRequests()
        scheduledCount = pending.filter { $0.identifier.hasPrefix(Self.managedPrefix) }.count
    }

    /// Permission and the in-app reminder preference are separate choices.
    func requestPermission() async {
        guard await readAuthorization() == .notDetermined else {
            await refreshStatus()
            return
        }
        _ = try? await requestAuthorization()
        await refreshStatus()
    }

    func reconcile() async {
        needsReconciliation = true
        if let reconciliationTask {
            await reconciliationTask.value
            return
        }
        let task = Task {
            while needsReconciliation {
                needsReconciliation = false
                await reconcilePendingRequests()
            }
            reconciliationTask = nil
        }
        reconciliationTask = task
        await task.value
    }

    private func reconcilePendingRequests() async {
        guard ReleaseNotificationPreferences.enabled else {
            await removeManagedRequests()
            await refreshStatus()
            return
        }

        let status = await readAuthorization()
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            await refreshStatus()
            return
        }

        guard let snapshot = try? await repository.releaseNotificationSnapshot() else {
            await refreshStatus()
            return
        }
        let notifications = ReleaseNotificationPolicy.notifications(
            from: snapshot,
            episodesEnabled: ReleaseNotificationPreferences.episodesEnabled,
            moviesEnabled: ReleaseNotificationPreferences.moviesEnabled,
            timing: ReleaseNotificationPreferences.timing
        )

        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(Self.managedPrefix) }
        let existing = Dictionary(uniqueKeysWithValues: pending.map { ($0.identifier, $0) })
        let desiredIDs = Set(notifications.map(\.identifier))
        let obsoleteIDs = existing.keys.filter { !desiredIDs.contains($0) }
        if !obsoleteIDs.isEmpty { center.removePendingNotificationRequests(withIdentifiers: obsoleteIDs) }

        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            content.categoryIdentifier = ReleaseNotificationAppDelegate.releaseCategoryIdentifier
            content.userInfo = userInfo(for: notification.destination)

            let components = Calendar.current.dateComponents(
                [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
                from: notification.fireDate
            )
            let request = UNNotificationRequest(
                identifier: notification.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            if let current = existing[request.identifier],
               current.content.title == content.title,
               current.content.body == content.body,
               current.content.categoryIdentifier == content.categoryIdentifier,
               NSDictionary(dictionary: current.content.userInfo).isEqual(NSDictionary(dictionary: content.userInfo)),
               (current.trigger as? UNCalendarNotificationTrigger)?.dateComponents == components {
                continue
            }
            try? await center.add(request)
        }
        await refreshStatus()
    }

    private func removeManagedRequests() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(Self.managedPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func userInfo(for destination: ScheduledReleaseNotification.Destination) -> [AnyHashable: Any] {
        switch destination {
        case let .media(mediaID):
            var userInfo: [AnyHashable: Any] = [
                "destination": "media",
                "kind": mediaID.kind.rawValue,
                "tmdbID": mediaID.tmdbID
            ]
            userInfo["traktID"] = mediaID.traktID
            return userInfo
        case let .episode(episode):
            var userInfo: [AnyHashable: Any] = [
                "destination": "episode",
                "showTMDbID": episode.showId,
                "season": episode.season,
                "episode": episode.episode
            ]
            userInfo["showTraktID"] = episode.showTraktID
            userInfo["tmdbID"] = episode.tmdbID
            userInfo["traktID"] = episode.traktID
            return userInfo
        }
    }
}

@MainActor
@Observable
final class ReleaseNotificationResponseStore {
    enum Destination: Identifiable, Equatable {
        case media(MediaID)
        case episode(EpisodeRef)

        var id: String {
            switch self {
            case let .media(mediaID): "media:\(mediaID.stableKey)"
            case let .episode(episode): "episode:\(episode.key)"
            }
        }
    }

    static let shared = ReleaseNotificationResponseStore()
    var destination: Destination?

    func handle(userInfo: [AnyHashable: Any]) {
        switch userInfo["destination"] as? String {
        case "media":
            guard let kindRaw = userInfo["kind"] as? String,
                  let kind = MediaKind(rawValue: kindRaw),
                  let tmdbID = userInfo["tmdbID"] as? Int else { return }
            destination = .media(MediaID(
                kind: kind,
                id: tmdbID,
                traktID: userInfo["traktID"] as? Int
            ))
        case "episode":
            guard let showID = userInfo["showTMDbID"] as? Int,
                  let season = userInfo["season"] as? Int,
                  let episode = userInfo["episode"] as? Int else { return }
            destination = .episode(EpisodeRef(
                showId: showID,
                showTraktID: userInfo["showTraktID"] as? Int,
                season: season,
                episode: episode,
                tmdbID: userInfo["tmdbID"] as? Int,
                traktID: userInfo["traktID"] as? Int
            ))
        default:
            break
        }
    }
}

final class ReleaseNotificationAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let releaseCategoryIdentifier = "RELEASE_REMINDER"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.releaseCategoryIdentifier,
                actions: [UNNotificationAction(identifier: "OPEN_RELEASE", title: "Open in iWatch")],
                intentIdentifiers: []
            )
        ])
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        ReleaseNotificationResponseStore.shared.handle(
            userInfo: response.notification.request.content.userInfo
        )
    }
}
