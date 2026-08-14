import SwiftUI
import SwiftData

// MARK: - App Content

struct ContentView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var notificationResponses = ReleaseNotificationResponseStore.shared

    var body: some View {
        @Bindable var router = router

        Group {
            if ProcessInfo.processInfo.arguments.contains("UITEST_MODE") {
                tabView
            } else {
                tabView
                    .tabBarMinimizeBehavior(.onScrollDown)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .task(id: session.libraryRevision) {
            await prewarmShows()
            await container.releaseNotificationCoordinator.reconcile()
        }
        .sheet(isPresented: $router.isShowingSettings) {
            SettingsSheet()
                .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .sheet(item: $notificationResponses.destination) { destination in
            NotificationDestinationView(destination: destination)
        }
        .overlay(alignment: .bottom) {
            if let feedback = session.transientFeedback {
                TransientFeedbackHUD(
                    message: feedback.message,
                    accessibilityMessage: feedback.accessibilityMessage
                )
                    .padding(.horizontal)
                    .padding(.bottom, 58)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: session.transientFeedback?.id)
    }

    private func prewarmShows() async {
        _ = try? await container.libraryRepository.showLibrarySnapshot(
            revision: session.libraryRevision
        )
    }

    private var tabView: some View {
        TabView(selection: Binding(
            get: { router.selectedTab },
            set: { router.selectedTab = $0 }
        )) {
            Tab("Movies", systemImage: "film", value: AppRouter.Tab.movies) {
                MoviesView()
            }

            Tab("Shows", systemImage: "tv", value: AppRouter.Tab.shows) {
                ShowsView()
            }

            if #available(iOS 27.0, *) {
                Tab(
                    "Search",
                    systemImage: "magnifyingglass",
                    value: AppRouter.Tab.search,
                    role: .prominent
                ) {
                    SearchView()
                }
            } else {
                Tab(
                    "Search",
                    systemImage: "magnifyingglass",
                    value: AppRouter.Tab.search,
                    role: .search
                ) {
                    SearchView()
                }
            }
        }
        // Links selecting the Search tab to search activation.
        // .tabViewSearchActivation(.searchTabSelection)
    }
}

private struct NotificationDestinationView: View {
    @Environment(\.dismiss) private var dismiss
    let destination: ReleaseNotificationResponseStore.Destination

    var body: some View {
        NavigationStack {
            Group {
                switch destination {
                case let .media(mediaID):
                    MediaDetailView(ref: mediaID)
                case let .episode(episode):
                    EpisodeView(ref: episode, onClose: { dismiss() })
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct TransientFeedbackHUD: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let message: String
    let accessibilityMessage: String

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
        } else {
            content
                .glassEffect(.regular, in: .capsule)
        }
    }

    private var content: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .imageScale(.large)
                .accessibilityHidden(true)

            Text(message)
                .font(.headline)
                .multilineTextAlignment(.leading)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityMessage)
        .accessibilityIdentifier("TransientFeedbackHUD")
        .allowsHitTesting(false)
    }
}

// MARK: - Previews

#Preview("Catalog") {
    let container = AppContainer.preview()
    ContentView()
        .environment(container)
        .environment(container.session)
        .environment(container.router)
        .modelContainer(container.persistence.modelContainer)
}

#Preview("TMDb Sandbox") {
    TMDbSandboxPreview()
}

// MARK: - Preview Support

private struct TMDbSandboxPreview: View {
    @State private var container = AppContainer.tmdbSandboxPreview()
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ContentView()
            .environment(container)
            .environment(container.session)
            .environment(container.router)
            .modelContainer(container.persistence.modelContainer)
            .overlay {
                if isLoading {
                    ProgressView("Loading TMDb Sandbox…")
                        .padding()
                        .glassEffect(in: .rect(cornerRadius: 16))
                } else if let errorMessage {
                    ContentUnavailableView(
                        "TMDb Sandbox Unavailable",
                        systemImage: "wifi.exclamationmark",
                        description: Text(errorMessage)
                    )
                }
            }
            .task {
                errorMessage = await container.loadTMDbSandboxCatalog()
                isLoading = false
            }
    }
}
