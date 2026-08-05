import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router

    var body: some View {
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
    }
}

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
