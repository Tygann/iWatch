import SwiftData
import StoreKit
import SwiftUI

// MARK: - Settings State

enum SettingsHomeSection: String, CaseIterable {
    case preferences = "Preferences"
}

// MARK: - Settings Screen

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.requestReview) private var requestReview

    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    // MARK: - Body
    var body: some View {
        Form {
            librarySection
            preferencesSection
            syncSection
            appSection
            storageAndDataSection
            #if DEBUG
            Section("Development") {
                NavigationLink("Reference Gallery") { ReferenceGallery() }
            }
            #endif
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.libraryRevision) { await session.refreshSyncDiagnostics() }
    }

    // MARK: - Library
    private var librarySection: some View {
        Section {
            NavigationLink {
                LibrarySettingsView()
            } label: {
                SettingsLibraryLabel(status: cloudStatus)
            }
            .accessibilityIdentifier("settings-library")
        }
    }

    // MARK: - Preferences Section
    private var preferencesSection: some View {
        Section(SettingsHomeSection.preferences.rawValue) {
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

            Picker(selection: Binding(
                get: { router.selectedTab.rawValue },
                set: { router.updateDefaultTab($0) }
            )) {
                Text("Movies").tag(AppRouter.Tab.movies.rawValue)
                Text("Shows").tag(AppRouter.Tab.shows.rawValue)
                Text("Search").tag(AppRouter.Tab.search.rawValue)
            } label: {
                Label("Start Page", systemImage: "platter.filled.bottom.iphone")
            }
            .pickerStyle(.menu)
            .tint(.secondary)

            NavigationLink {
                ReleaseNotificationsSettingsView()
            } label: {
                SettingsNavigationLabel(
                    title: "Notifications",
                    systemImage: "bell",
                    detail: notificationStatus
                )
            }
        }
    }

    // MARK: - Sync Section
    private var syncSection: some View {
        Section {
            NavigationLink {
                TraktSettingsView()
            } label: {
                SettingsNavigationLabel(
                    title: "Trakt Sync",
                    systemImage: "checkmark.arrow.trianglehead.clockwise",
                    detail: traktStatus
                )
            }
            .accessibilityIdentifier("settings-trakt-sync")
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
    private var traktStatus: String? {
        let health = session.traktSyncPresentation
        if health.needsAttention { return "Needs Attention" }
        if health.isWorking { return health.title }
        return session.traktConnected ? nil : "Not Connected"
    }

    private var cloudStatus: String? {
        switch session.cloudSyncStatus {
        case .importing, .exporting: session.cloudSyncStatus.title
        case .failed, .unavailable, .timedOut: "Needs Attention"
        default: nil
        }
    }

    private var notificationStatus: String {
        ReleaseNotificationPreferences.enabled ? "On" : "Off"
    }
}

// MARK: - Settings Components

private struct SettingsLibraryLabel: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let status: String?

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            if !typeSize.isAccessibilitySize {
                Image(systemName: "books.vertical")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.control))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("Your Library").font(.headline)
                Text("iCloud sync").font(.subheadline).foregroundStyle(.secondary)
                if let status {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, AppSpacing.small)
        .accessibilityElement(children: .combine)
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

// MARK: - Previews
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
