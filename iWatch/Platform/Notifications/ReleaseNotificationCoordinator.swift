import Foundation
import Observation
import UIKit
import UserNotifications

enum ReleaseNotificationPreferences {
    static let enabledKey = "releaseNotificationsEnabled"
    static let episodesEnabledKey = "episodeReleaseNotificationsEnabled"
    static let moviesEnabledKey = "movieReleaseNotificationsEnabled"
    static let timingKey = "releaseNotificationTiming"

    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var episodesEnabled: Bool {
        UserDefaults.standard.object(forKey: episodesEnabledKey) as? Bool ?? true
    }
    static var moviesEnabled: Bool {
        UserDefaults.standard.object(forKey: moviesEnabledKey) as? Bool ?? true
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

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var scheduledCount = 0

    init(
        repository: LibraryRepository,
        center: UNUserNotificationCenter = .current()
    ) {
        self.repository = repository
        self.center = center
    }

    func refreshStatus() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
        let pending = await center.pendingNotificationRequests()
        scheduledCount = pending.filter { $0.identifier.hasPrefix(Self.managedPrefix) }.count
    }

    func setEnabled(_ enabled: Bool) async -> Bool {
        guard enabled else {
            await removeManagedRequests()
            await refreshStatus()
            return false
        }

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                guard try await center.requestAuthorization(options: [.alert, .badge, .sound]) else {
                    await refreshStatus()
                    return false
                }
            } catch {
                await refreshStatus()
                return false
            }
        case .denied:
            await refreshStatus()
            return false
        case .authorized, .provisional, .ephemeral:
            break
        @unknown default:
            return false
        }

        await reconcile()
        return true
    }

    func reconcile() async {
        guard ReleaseNotificationPreferences.enabled else {
            await removeManagedRequests()
            await refreshStatus()
            return
        }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional ||
                settings.authorizationStatus == .ephemeral else {
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

        await removeManagedRequests()
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
