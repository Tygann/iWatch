import SwiftUI
import SwiftData

// MARK: - App Content

struct ContentView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router

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
        .task(id: session.libraryRevision) {
            await prewarmShows()
        }
        .sheet(isPresented: $router.isShowingSettings) {
            SettingsSheet()
        }
        .overlay(alignment: .bottom) {
            if let feedback = session.transientFeedback {
                TransientFeedbackHUD(message: feedback.message)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 72)
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

private struct TransientFeedbackHUD: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .imageScale(.large)
                .accessibilityHidden(true)

            Text(message)
                .font(.headline)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
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
