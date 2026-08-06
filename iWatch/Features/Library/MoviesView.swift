import SwiftUI
import Observation
import SwiftData

@MainActor
@Observable
private final class MoviesScreenModel {
    private let repository: LibraryRepository
    private let session: AppSession

    var items: [LibraryMovieItem] = []
    var isLoading = false
    var isEnriching = false
    var errorText: String?
    private var loadedRevision: Int?
    private var enrichedRevision: Int?

    init(repository: LibraryRepository, session: AppSession) {
        self.repository = repository
        self.session = session
    }

    func load(revision: Int, forceRefresh: Bool = false) async {
        guard forceRefresh || loadedRevision != revision else { return }
        let shouldShowLoading = items.isEmpty
        if shouldShowLoading { isLoading = true }
        defer { isLoading = false }

        do {
            items = try await repository.movieLibraryItems(revision: revision, forceRefresh: forceRefresh)
            loadedRevision = revision
            errorText = nil
        } catch {
            guard !error.isCancelled else { return }
            errorText = error.localizedDescription
            items = []
        }
    }

    func enrichMissingMetadata() async {
        let revision = session.libraryRevision
        guard !isEnriching, enrichedRevision != revision else { return }
        isEnriching = true
        defer {
            isEnriching = false
            if !Task.isCancelled {
                enrichedRevision = revision
            }
        }

        let missing = items.filter { $0.posterPath == nil }
        for item in missing {
            guard !Task.isCancelled else { return }
            do {
                try await repository.enrichMetadata(for: item.mediaID)
            } catch {
                guard !error.isCancelled else { return }
                // Metadata is optional; keep the imported library usable if enrichment fails.
            }
        }
        if !missing.isEmpty {
            await load(revision: session.libraryRevision, forceRefresh: true)
        }
    }

    var watchlistItems: [LibraryMovieItem] {
        items
            .filter(\.isInWatchlist)
            .sorted { ($0.listedAt ?? .distantPast) > ($1.listedAt ?? .distantPast) }
    }

    var watchedItems: [LibraryMovieItem] {
        items
            .filter(\.isWatched)
            .sorted { ($0.lastWatchedAt ?? .distantPast) > ($1.lastWatchedAt ?? .distantPast) }
    }

    func markWatched(_ item: LibraryMovieItem) async {
        do {
            try await repository.addWatchEvent(for: item.mediaID, watchedAt: Date())
            session.markLibraryUpdated(syncIfConnected: true)
            await load(revision: session.libraryRevision)
        } catch {
            errorText = error.localizedDescription
        }
    }

    func markUnwatched(_ item: LibraryMovieItem) async {
        if let eventID = await repository.latestWatchEventID(for: item.mediaID) {
            do {
                try await repository.removeWatchEvent(eventID: eventID)
                session.markLibraryUpdated(syncIfConnected: true)
            await load(revision: session.libraryRevision)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}

struct MoviesView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AppSession.self) private var session

    @State private var model: MoviesScreenModel?
    @State private var showSettings = false

    var body: some View {
        Group {
            if let model {
                MoviesViewBody(
                    model: model,
                    showSettings: $showSettings
                )
            } else {
                ProgressView()
                    .task {
                        let newModel = MoviesScreenModel(repository: container.libraryRepository, session: session)
                        model = newModel
                    }
            }
        }
    }
}

private struct MoviesViewBody: View {
    @Bindable var model: MoviesScreenModel
    @Binding var showSettings: Bool
    @Environment(AppSession.self) private var session

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorText = model.errorText {
                    ContentUnavailableView("Movies Error",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(errorText))
                } else if model.items.isEmpty {
                    ContentUnavailableView(
                        "No movies yet",
                        systemImage: "film",
                        description: Text("Add movies to your Watchlist from Search.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        toWatchSection
                        watchedSection
                    }
                }
            }
            .navigationTitle("Movies")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: {
                        Image(systemName: "person.crop.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.primary, .clear)
                            .scaleEffect(1.5)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .task(id: session.libraryRevision) {
                await model.load(revision: session.libraryRevision)
                await model.enrichMissingMetadata()
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button(role: .close) { showSettings = false }
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var toWatchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("To Watch")
                .font(.title3.weight(.bold))
                .padding(.horizontal)

            if model.watchlistItems.isEmpty {
                ContentUnavailableView(
                    "Nothing to watch",
                    systemImage: "checkmark.circle",
                    description: Text("Add movies from Search to your Watchlist.")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(model.watchlistItems) { item in
                        movieTile(item, showTitle: false)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var watchedSection: some View {
        if !model.watchedItems.isEmpty {
            MediaCollectionRow(title: "Watched") {
                MovieCollectionView(
                    title: "Watched",
                    items: model.watchedItems,
                    markUnwatched: model.markUnwatched
                )
            } content: {
                ForEach(model.watchedItems.prefix(12)) { item in
                    movieTile(item, showTitle: false)
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func movieTile(_ item: LibraryMovieItem, showTitle: Bool) -> some View {
        MediaTile(
            ref: item.mediaID,
            title: item.title,
            posterPath: item.posterPath,
            showTitle: showTitle,
            extraMenu: {
                if item.isWatched {
                    Button {
                        Haptics.notification(.success)
                        Task { await model.markWatched(item) }
                    } label: {
                        Label("Add Rewatch", systemImage: "arrow.clockwise")
                    }
                    Button {
                        Haptics.notification(.success)
                        Task { await model.markUnwatched(item) }
                    } label: {
                        Label("Remove Latest Play", systemImage: "arrow.uturn.backward.circle")
                    }
                } else {
                    Button {
                        Haptics.notification(.success)
                        Task { await model.markWatched(item) }
                    } label: {
                        Label("Mark as Watched", systemImage: "checkmark.circle")
                    }
                }
                Divider()
            }
        )
        .onTapGesture(count: 2) {
            Haptics.notification(.success)
            Task { await model.markWatched(item) }
        }
        .frame(width: 110)
    }
}

private struct MovieCollectionView: View {
    let title: String
    let items: [LibraryMovieItem]
    let markUnwatched: (LibraryMovieItem) async -> Void

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(items) { item in
                    MediaTile(
                        ref: item.mediaID,
                        title: item.title,
                        posterPath: item.posterPath,
                        showTitle: true,
                        extraMenu: {
                            Button {
                                Haptics.notification(.success)
                                Task { await markUnwatched(item) }
                            } label: {
                                Label("Remove Latest Play", systemImage: "arrow.uturn.backward.circle")
                            }
                            Divider()
                        }
                    )
                    .frame(width: 110)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let container = AppContainer.preview()
    MoviesView()
        .environment(container)
        .environment(container.session)
        .environment(container.router)
        .modelContainer(container.persistence.modelContainer)
}
