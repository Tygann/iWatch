import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct ReleaseNotificationsSettingsView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openURL) private var openURL

    @AppStorage(ReleaseNotificationPreferences.enabledKey) private var isEnabled = false
    @AppStorage(ReleaseNotificationPreferences.episodesEnabledKey) private var episodesEnabled = true
    @AppStorage(ReleaseNotificationPreferences.moviesEnabledKey) private var moviesEnabled = true
    @AppStorage(ReleaseNotificationPreferences.timingKey) private var timing = ReleaseNotificationTiming.atRelease

    @State private var isUpdatingAuthorization = false

    private var coordinator: ReleaseNotificationCoordinator {
        container.releaseNotificationCoordinator
    }

    var body: some View {
        Form {
            Section {
                Toggle("Release Notifications", isOn: Binding(
                    get: { isEnabled },
                    set: updateEnabled
                ))
                .disabled(isUpdatingAuthorization)

                if coordinator.authorizationStatus == .denied {
                    Button("Open System Settings") {
                        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
                        openURL(url)
                    }
                }
            } footer: {
                Text("Get reminders for releases already in your iWatch library.")
            }

            Section("Releases") {
                Toggle("TV Episodes", isOn: $episodesEnabled)
                Toggle("Movies", isOn: $moviesEnabled)
            }
            .disabled(!isEnabled)

            Section {
                Picker("Notify Me", selection: $timing) {
                    ForEach(ReleaseNotificationTiming.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.navigationLink)

                LabeledContent("Time Zone", value: TimeZone.current.localizedName(for: .standard, locale: .current) ?? TimeZone.current.identifier)
            } footer: {
                Text("When an exact episode airtime isn’t available, iWatch sends the reminder at 9:00 AM local time. Movie reminders are always sent the morning of release.")
            }
            .disabled(!isEnabled)

            if isEnabled {
                Section("Status") {
                    LabeledContent("Scheduled", value: "\(coordinator.scheduledCount)")
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await coordinator.refreshStatus()
        }
        .onChange(of: episodesEnabled) { _, _ in reconcile() }
        .onChange(of: moviesEnabled) { _, _ in reconcile() }
        .onChange(of: timing) { _, _ in reconcile() }
    }

    private func updateEnabled(_ newValue: Bool) {
        guard !isUpdatingAuthorization else { return }
        isEnabled = newValue
        isUpdatingAuthorization = true
        Task {
            let enabled = await coordinator.setEnabled(newValue)
            isEnabled = enabled
            isUpdatingAuthorization = false
        }
    }

    private func reconcile() {
        guard isEnabled else { return }
        Task { await coordinator.reconcile() }
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
