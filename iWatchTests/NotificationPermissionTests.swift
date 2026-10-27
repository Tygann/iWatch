import Foundation
import Testing
import UserNotifications
@testable import iWatch

@Suite @MainActor
struct NotificationPermissionTests {
    @Test
    func permissionPresentationDistinguishesSystemAccess() {
        #expect(NotificationPermissionPresentation.resolve(.denied).action == .settings)
        #expect(NotificationPermissionPresentation.resolve(.notDetermined).action == .allow)
        #expect(NotificationPermissionPresentation.resolve(.authorized).action == .none)
        #expect(NotificationPermissionPresentation.resolve(.provisional).detail.contains("quietly"))
    }

    @Test
    func refreshReflectsChangesMadeOutsideTheApp() async {
        let container = AppContainer.preview(seedCatalog: false)
        let status = TestValue(UNAuthorizationStatus.denied)
        let coordinator = ReleaseNotificationCoordinator(repository: container.libraryRepository,
            readAuthorization: { status.value }, requestAuthorization: { false })
        await coordinator.refreshStatus()
        #expect(coordinator.authorizationStatus == .denied)
        status.value = .authorized
        await coordinator.refreshStatus()
        #expect(coordinator.authorizationStatus == .authorized)
    }

    @Test
    func requestingPermissionDoesNotChangeReminderPreference() async {
        let container = AppContainer.preview(seedCatalog: false)
        let original = ReleaseNotificationPreferences.enabled
        let status = TestValue(UNAuthorizationStatus.notDetermined)
        let coordinator = ReleaseNotificationCoordinator(repository: container.libraryRepository,
            readAuthorization: { status.value }, requestAuthorization: { status.value = .authorized; return true })
        await coordinator.requestPermission()
        #expect(coordinator.authorizationStatus == .authorized)
        #expect(ReleaseNotificationPreferences.enabled == original)
    }
}
