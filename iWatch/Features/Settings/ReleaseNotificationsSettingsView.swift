import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct ReleaseNotificationsSettingsView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var settingsOpenFailed = false

    @AppStorage(ReleaseNotificationPreferences.episodesEnabledKey) private var episodesEnabled = false
    @AppStorage(ReleaseNotificationPreferences.moviesEnabledKey) private var moviesEnabled = false
    @AppStorage(ReleaseNotificationPreferences.timingKey) private var timing = ReleaseNotificationTiming.atRelease

    @State private var isUpdatingAuthorization = false

    private var coordinator: ReleaseNotificationCoordinator {
        container.releaseNotificationCoordinator
    }

    var body: some View {
        Form {
            Section {
                SettingsStatusRow(title: "System Notifications", detail: permission.detail, symbol: "bell.badge",
                                  needsAttention: coordinator.authorizationStatus == .denied) {
                    if isUpdatingAuthorization {
                        ProgressView().accessibilityLabel("Updating notification access")
                    } else if permission.action == .settings {
                        Button {
                            openNotificationSettings()
                        } label: {
                            Text("Settings")
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Notification Settings")
                        .disabled(container.session.isReadOnlyPreview)
                    }
                }
            }

            if settingsOpenFailed {
                Section { Text("iOS Settings couldn’t be opened. Open Settings > Notifications > iWatch.") }
            }
            Section {
                Toggle("TV Episodes", isOn: $episodesEnabled)
                Toggle("Movies", isOn: $moviesEnabled)
            } header: {
                Text("Releases")
            } footer: {
                Text("Get reminders for releases already in your iWatch library.")
            }
            .disabled(isUpdatingAuthorization)

            Section {
                Picker("Notify Me", selection: $timing) {
                    ForEach(ReleaseNotificationTiming.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.navigationLink)
            } footer: {
                Text("When an exact episode airtime isn’t available, iWatch sends the reminder at 9:00 AM local time. Movie reminders are always sent the morning of release.")
            }
            .disabled(!episodesEnabled && !moviesEnabled)

            if episodesEnabled || moviesEnabled {
                Section("Status") {
                    LabeledContent("Scheduled Reminders", value: "\(coordinator.scheduledCount)")
                }
            }
        }
        .disabled(container.session.isReadOnlyPreview)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await coordinator.refreshStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !container.session.isReadOnlyPreview else { return }
            Task { await coordinator.reconcile() }
        }
        .onChange(of: episodesEnabled) { _, enabled in updateReminders(requestPermission: enabled) }
        .onChange(of: moviesEnabled) { _, enabled in updateReminders(requestPermission: enabled) }
        .onChange(of: timing) { _, _ in updateReminders() }
    }

    private var permission: NotificationPermissionPresentation {
        .resolve(coordinator.authorizationStatus)
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        openURL(url) { accepted in settingsOpenFailed = !accepted }
    }

    private func updateReminders(requestPermission: Bool = false) {
        guard !container.session.isReadOnlyPreview else { return }
        let shouldRequestPermission = requestPermission
            && coordinator.authorizationStatus == .notDetermined
            && !isUpdatingAuthorization
        if shouldRequestPermission {
            isUpdatingAuthorization = true
        }
        Task {
            if shouldRequestPermission {
                await coordinator.requestPermission()
                isUpdatingAuthorization = false
            }
            await coordinator.reconcile()
        }
    }
}

#Preview {
    let container = AppContainer.preview()
    NavigationStack {
        ReleaseNotificationsSettingsView()
    }
    .environment(container)
    .environment(container.session)
    .environment(container.router)
    .modelContainer(container.persistence.modelContainer)
}
