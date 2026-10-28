import UserNotifications

struct NotificationPermissionPresentation: Equatable {
    enum Action { case allow, settings, none }
    let detail: String
    let action: Action

    static func summary(enabled: Bool, status: UNAuthorizationStatus) -> String {
        guard enabled else { return "Off" }
        switch status {
        case .authorized, .ephemeral: return "On"
        case .provisional: return "Delivered Quietly"
        case .denied: return "Blocked in iOS Settings"
        case .notDetermined: return "Permission Needed"
        @unknown default: return "Check iOS Settings"
        }
    }

    static func resolve(_ status: UNAuthorizationStatus) -> Self {
        switch status {
        case .notDetermined: Self(detail: "Permission hasn’t been requested.", action: .allow)
        case .denied: Self(detail: "Off in iOS Settings.", action: .settings)
        case .authorized: Self(detail: "Allowed by iOS.", action: .none)
        case .provisional: Self(detail: "Delivered quietly by iOS.", action: .settings)
        case .ephemeral: Self(detail: "Temporarily allowed by iOS.", action: .none)
        @unknown default: Self(detail: "Managed by iOS.", action: .settings)
        }
    }
}
