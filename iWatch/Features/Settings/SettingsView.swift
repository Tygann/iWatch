import SwiftData
import StoreKit
import SwiftUI

// MARK: - Settings State

enum SettingsHomeSection: String, CaseIterable {
    case preferences = "Preferences"
    case support = "Support"
    case app = "App"
}

// MARK: - Settings Screen

struct SettingsView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @AppStorage(ReleaseNotificationPreferences.enabledKey) private var notificationsEnabled = false
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router

    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    // MARK: - Body
    var body: some View {
        Form {
            librarySection
            preferencesSection
            supportSection
            appSection
            #if DEBUG
            Section("Development") {
                NavigationLink("Reference Gallery") { ReferenceGallery() }
            }
            #endif
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.libraryRevision) { await session.refreshSyncDiagnostics() }
        .task { await container.releaseNotificationCoordinator.refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await container.releaseNotificationCoordinator.refreshStatus() }
            }
        }
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
                SettingsNavigationLabel(title: "Appearance", systemImage: "circle.righthalf.filled")
            }
            .pickerStyle(.menu)
            .tint(.secondary)

            Picker(selection: Binding(
                get: { router.defaultTab.rawValue },
                set: { router.updateDefaultTab($0) }
            )) {
                Text("Movies").tag(AppRouter.Tab.movies.rawValue)
                Text("Shows").tag(AppRouter.Tab.shows.rawValue)
                Text("Search").tag(AppRouter.Tab.search.rawValue)
            } label: {
                SettingsNavigationLabel(title: "Start Page", systemImage: "platter.filled.bottom.iphone")
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

    private var supportSection: some View {
        Section(SettingsHomeSection.support.rawValue) {
            NavigationLink { SyncSupportView() } label: {
                SettingsNavigationLabel(title: "Contact Support", systemImage: "questionmark.circle")
            }
            .accessibilityIdentifier("settings-support")
        }
    }

    private var appSection: some View {
        Section(SettingsHomeSection.app.rawValue) {
            ShareLink(item: AppDistributionPresentation.shareText) {
                SettingsNavigationLabel(title: "Share iWatch", systemImage: "square.and.arrow.up")
            }
            Button { requestReview() } label: {
                SettingsNavigationLabel(title: "Rate iWatch", systemImage: "star")
            }
            NavigationLink { AboutView() } label: {
                SettingsNavigationLabel(title: "About", systemImage: "info.circle")
            }
            .accessibilityIdentifier("settings-about")
        }
    }

    private var cloudStatus: String? {
        if session.pendingTraktAccountKey != nil { return "Finish Trakt Setup" }
        if session.traktSyncPresentation.needsAttention { return "Trakt Needs Attention" }
        if session.traktSyncPresentation.isWorking { return "Trakt: " + session.traktSyncPresentation.title }
        switch session.cloudSyncStatus {
        case .importing, .exporting: return "iCloud: " + session.cloudSyncStatus.title
        case .failed, .unavailable, .timedOut: return "iCloud Needs Attention"
        default: return nil
        }
    }

    private var notificationStatus: String {
        NotificationPermissionPresentation.summary(enabled: notificationsEnabled,
            status: container.releaseNotificationCoordinator.authorizationStatus)
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
                Text(status ?? "Watchlist, history, and sync")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, AppSpacing.small)
        .accessibilityElement(children: .combine)
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
