import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router

    @AppStorage("hideEndedShows") private var hideEndedShows = false
    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    var body: some View {
        Form {
            preferencesSection
            syncSection
            appSection
            advancedSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var preferencesSection: some View {
        Section("Preferences") {
            Picker(selection: Binding(
                get: { router.selectedTab.rawValue },
                set: { router.updateDefaultTab($0) }
            )) {
                Text("Movies").tag(AppRouter.Tab.movies.rawValue)
                Text("Shows").tag(AppRouter.Tab.shows.rawValue)
                Text("Search").tag(AppRouter.Tab.search.rawValue)
            } label: {
                Label("Default Tab", systemImage: "rectangle.3.group")
            }

            Toggle(isOn: $hideEndedShows) {
                Label("Hide Ended Shows", systemImage: "eye.slash")
            }

            NavigationLink {
                AppThemeView()
            } label: {
                SettingsNavigationLabel(
                    title: "App Appearance",
                    systemImage: "circle.lefthalf.filled",
                    detail: appTheme.title
                )
            }
        }
    }

    private var syncSection: some View {
        Section {
            NavigationLink {
                TraktSettingsView()
            } label: {
                SettingsNavigationLabel(
                    title: "Trakt",
                    systemImage: "link",
                    detail: traktStatus
                )
            }

            LabeledContent {
                Text("Automatic")
                    .foregroundStyle(.secondary)
            } label: {
                Label("iCloud", systemImage: "icloud")
            }
        } header: {
            Text("Sync")
        } footer: {
            Text("iCloud keeps your library available across your Apple devices. Trakt is optional and syncs separately.")
        }
    }

    private var appSection: some View {
        Section("App") {
            NavigationLink {
                StorageSettingsView()
            } label: {
                Label("Temporary Files", systemImage: "internaldrive")
            }

            NavigationLink {
                AboutView()
            } label: {
                Label("About iWatch", systemImage: "info.circle")
            }
        }
    }

    private var advancedSection: some View {
        Section {
            NavigationLink {
                ResetDataView()
            } label: {
                Label("Reset iWatch", systemImage: "arrow.counterclockwise")
            }
        } footer: {
            Text("Permanently erase your iWatch library, preferences, and synced iCloud data.")
        }
    }

    private var traktStatus: String {
        if session.traktIsConnecting {
            return "Connecting…"
        }
        if session.isSyncing {
            return "Syncing…"
        }
        return session.traktConnected ? "Connected" : "Not Connected"
    }
}

struct SettingsNavigationLabel: View {
    let title: String
    let systemImage: String
    var detail: String?

    var body: some View {
        LabeledContent {
            if let detail {
                Text(detail)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

#Preview {
    let container = AppContainer.preview()
    NavigationStack {
        SettingsView()
    }
    .environment(container)
    .environment(container.session)
    .environment(container.router)
    .modelContainer(container.persistence.modelContainer)
}
