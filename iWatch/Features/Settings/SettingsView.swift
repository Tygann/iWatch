import SwiftData
import StoreKit
import SwiftUI

enum SettingsHomeSection: String, CaseIterable {
    case preferences = "Preferences"
    case sync = "Sync"
}

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.requestReview) private var requestReview

    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    // MARK: - Body
    var body: some View {
        Form {
            preferencesSection
            syncSection
            appSection
            storageAndDataSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Preferences Section
    private var preferencesSection: some View {
        Section(SettingsHomeSection.preferences.rawValue) {
            Picker(selection: Binding(
                get: { router.selectedTab.rawValue },
                set: { router.updateDefaultTab($0) }
            )) {
                Text("Movies").tag(AppRouter.Tab.movies.rawValue)
                Text("Shows").tag(AppRouter.Tab.shows.rawValue)
                Text("Search").tag(AppRouter.Tab.search.rawValue)
            } label: {
                Label("Default Tab", systemImage: "platter.filled.bottom.iphone")
            }
            .pickerStyle(.menu)
            .tint(.secondary)

            Picker(selection: $appTheme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.title)
                        .tag(theme)
                }
            } label: {
                Label("Appearance", systemImage: "circle.righthalf.filled")
            }
            .pickerStyle(.menu)
            .tint(.secondary)
        }
    }

    // MARK: - Sync Section
    private var syncSection: some View {
        Section {
            NavigationLink {
                TraktSettingsView()
            } label: {
                SettingsNavigationLabel(
                    title: "Trakt",
                    systemImage: "checkmark.arrow.trianglehead.clockwise",
                    detail: traktStatus
                )
            }

            LabeledContent {
                Text("Automatic")
                    .foregroundStyle(.secondary)
            } label: {
                Label("iCloud Sync", systemImage: "icloud")
            }
        } header: {
            Text(SettingsHomeSection.sync.rawValue)
        } footer: {
            Text("iCloud syncs your library across Apple devices. Trakt sync is optional.")
        }
    }

    // MARK: - App Section
    private var appSection: some View {
        Section {
            ShareLink(
                item: AppDistributionPresentation.shareText,
                preview: SharePreview("iWatch")
            ) {
                Label("Share iWatch", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)

            Button {
                requestReview()
            } label: {
                Label("Rate iWatch", systemImage: "star")
            }
            .buttonStyle(.plain)

            NavigationLink {
                AboutView()
            } label: {
                Label("About", systemImage: "info.circle")
            }
        }
    }

    // MARK: - Storage & Data Section
    private var storageAndDataSection: some View {
        Section {
            NavigationLink {
                AdvancedSettingsView()
            } label: {
                Label("Storage & Data", systemImage: "internaldrive")
            }
        }
    }

    // MARK: - Helpers
    private var traktStatus: String {
        Self.traktStatus(
            isConnecting: session.traktIsConnecting,
            isSyncing: session.isSyncing,
            isConnected: session.traktConnected,
            needsAttention: session.traktLastError != nil || session.syncDiagnostics.deadletterOperationCount > 0
        )
    }

    static func traktStatus(
        isConnecting: Bool,
        isSyncing: Bool,
        isConnected: Bool,
        needsAttention: Bool
    ) -> String {
        if isConnecting {
            return "Connecting…"
        }
        if isSyncing {
            return "Syncing…"
        }
        if needsAttention {
            return "Needs Attention"
        }
        return isConnected ? "Connected" : "Not Connected"
    }
}

struct SettingsNavigationLabel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let systemImage: String
    var detail: String?

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
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
}

// MARK: - Preview
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
