#if DEBUG
import SwiftUI
import SwiftData
import UserNotifications

/// Deterministic, read-only reference states. No credentials or provider requests are needed.
struct ReferenceGallery: View {
    var body: some View {
        List {
            Section("Library") {
                NavigationLink("Empty Library") { ReferenceLibraryView(state: .empty) }
                NavigationLink("Large Library") { ReferenceLibraryView(state: .large) }
                NavigationLink("Offline Library") { ReferenceLibraryView(state: .offline) }
                NavigationLink("Loading Library") { ReferenceLibraryView(state: .loading) }
            }
            Section("Settings") {
                NavigationLink("Notifications — Blocked") { ReferenceSettingsView(scenario: .notifications) }
                NavigationLink("Trakt — Synced") { ReferenceSettingsView(scenario: .synced) }
                NavigationLink("Trakt — Pending Confirmation") { ReferenceSettingsView(scenario: .confirmation) }
                NavigationLink("Trakt — Offline") { ReferenceSettingsView(scenario: .offline) }
                NavigationLink("Trakt — Importing") { ReferenceSettingsView(scenario: .importing) }
                NavigationLink("iCloud — Unavailable") { ReferenceSettingsView(scenario: .cloud) }
            }
        }
        .navigationTitle("Reference Gallery")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ReferenceLibraryView: View {
    enum State { case empty, large, offline, loading }
    @Environment(\.dynamicTypeSize) private var typeSize
    let state: State
    @State private var showsError = true

    var body: some View {
        Group {
            switch state {
            case .empty:
                ContentUnavailableView("No movies yet", systemImage: "film",
                    description: Text("Add movies to your Watchlist from Search."))
            case .loading:
                ProgressView("Loading library…")
            case .large, .offline:
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.large) {
                        if state == .offline, showsError {
                            RecoveryNotice(message: "Check your connection, then try again.") { showsError = false }
                        }
                        Text("To Watch").font(.title2.bold())
                        LazyVGrid(columns: typeSize.isAccessibilitySize
                            ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 110))], spacing: AppSpacing.large) {
                            ForEach(1...(state == .large ? 250 : 6), id: \.self) { index in
                                VStack {
                                    PosterImage(path: nil)
                                    Text("Sample Movie \(index)").font(.caption)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    .padding(AppSpacing.large)
                }
            }
        }
        .navigationTitle("Movies")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ReferenceSettingsView: View {
    enum Scenario { case notifications, synced, confirmation, offline, importing, cloud }
    let scenario: Scenario
    @State private var container: AppContainer

    init(scenario: Scenario) {
        self.scenario = scenario
        let container = AppContainer.preview(seedCatalog: false, notificationStatus: .denied)
        container.session.isReferencePreview = true
        let state: String
        switch scenario {
        case .confirmation: state = "confirmation"
        case .offline, .cloud: state = "offline"
        case .importing: state = "syncing"
        default: state = "normal"
        }
        container.session.applySyncSettingsFixture(state)
        _container = State(initialValue: container)
    }

    var body: some View {
        Group {
            switch scenario {
            case .notifications: ReleaseNotificationsSettingsView()
            case .cloud: ICloudSyncSettingsView()
            default: TraktSettingsView()
            }
        }
        .environment(container)
        .environment(container.session)
        .environment(container.router)
        .modelContainer(container.persistence.modelContainer)
    }
}

#Preview("Reference Gallery") {
    NavigationStack { ReferenceGallery() }
}
#endif
