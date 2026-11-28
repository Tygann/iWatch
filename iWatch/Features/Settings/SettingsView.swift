import SwiftData
import StoreKit
import SwiftUI

// MARK: - Settings State

enum SettingsHomeSection: String, CaseIterable {
    case preferences = "Preferences"
    case app = "App"
}

// MARK: - Settings Screen

struct SettingsView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @AppStorage(ReleaseNotificationPreferences.episodesEnabledKey) private var episodesEnabled = false
    @AppStorage(ReleaseNotificationPreferences.moviesEnabledKey) private var moviesEnabled = false
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router

    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    // MARK: - Body
    var body: some View {
        Form {
            accountSection
            librarySection
            preferencesSection
            appSection
            #if DEBUG
            Section("Development") {
                NavigationLink { ReferenceGallery() } label: {
                    SettingsNavigationLabel(title: "Reference Gallery", systemImage: "hammer", tint: .gray)
                }
            }
            #endif
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.libraryRevision) { await session.refreshSyncDiagnostics() }
        .task { await container.releaseNotificationCoordinator.refreshStatus() }
        .task { await container.account.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await container.releaseNotificationCoordinator.refreshStatus() }
            }
        }
    }

    private var accountSection: some View {
        Section {
            NavigationLink {
                AccountView(account: container.account)
            } label: {
                HStack(spacing: AppSpacing.large) {
                    AccountAvatar(localPhoto: container.account.photo, size: 60)
                    VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                        if container.account.userID == nil || container.account.displayName != nil {
                            Text(container.account.title).font(.headline).fontDesign(.rounded)
                            Text("Account").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            Text("Account").font(.headline).fontDesign(.rounded)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, AppSpacing.small)
                .accessibilityElement(children: .combine)
            }
            .accessibilityIdentifier("settings-account")
        }
    }

    private var librarySection: some View {
        Section("Library") {
            NavigationLink {
                LibrarySettingsView()
            } label: {
                SettingsNavigationLabel(
                    title: "Library Sync",
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: .purple,
                    detail: syncStatus
                )
            }
            .accessibilityIdentifier("settings-sync")
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
                SettingsNavigationLabel(title: "Appearance", systemImage: "circle.righthalf.filled", tint: .black)
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
                SettingsNavigationLabel(title: "Start Page", systemImage: "platter.filled.bottom.iphone", tint: .blue)
            }
            .pickerStyle(.menu)
            .tint(.secondary)

            NavigationLink {
                ReleaseNotificationsSettingsView()
            } label: {
                SettingsNavigationLabel(
                    title: "Notifications",
                    systemImage: "bell.badge.fill",
                    tint: .red,
                    detail: notificationStatus
                )
            }
        }
    }

    private var appSection: some View {
        Section(SettingsHomeSection.app.rawValue) {
            ShareLink(item: AppDistributionPresentation.shareText) {
                SettingsNavigationLabel(title: "Share iWatch", systemImage: "square.and.arrow.up", tint: .blue)
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            Button { requestReview() } label: {
                SettingsNavigationLabel(title: "Rate iWatch", systemImage: "star.fill", tint: .purple)
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            NavigationLink { AboutView() } label: {
                SettingsNavigationLabel(title: "About", systemImage: "info.circle", tint: .gray)
            }
            .accessibilityIdentifier("settings-about")
        }
    }

    private var syncStatus: String? {
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
        NotificationPermissionPresentation.summary(enabled: episodesEnabled || moviesEnabled,
            status: container.releaseNotificationCoordinator.authorizationStatus)
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
