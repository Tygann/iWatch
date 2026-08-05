import SwiftUI
import Observation

@MainActor
@Observable
private final class WatchlistScreenModel {
    let kind: MediaKind
    private let repository: LibraryRepository
    private let session: AppSession

    var movieItems: [LibraryMovieItem] = []
    var showItems: [LibraryShowItem] = []
    var isLoading = false
    var errorText: String?
    private var loadedRevision: Int?

    init(
        kind: MediaKind,
        repository: LibraryRepository,
        session: AppSession,
        initialShowItems: [LibraryShowItem] = [],
        initialRevision: Int? = nil
    ) {
        self.kind = kind
        self.repository = repository
        self.session = session
        self.showItems = initialShowItems
        self.loadedRevision = initialRevision
    }

    func load(revision: Int) async {
        guard loadedRevision != revision else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            if kind == .movie {
                movieItems = try await repository.movieLibraryItems(revision: revision)
                    .filter(\.isInWatchlist)
            } else {
                showItems = try await repository.showLibrarySnapshot(revision: revision).continueWatching
            }
            loadedRevision = revision
            errorText = nil
        } catch {
            guard !error.isCancelled else { return }
            errorText = error.localizedDescription
        }
    }

    var title: String { kind == .movie ? "Watchlist" : "Continue Watching" }

    func markNextEpisodeWatched(for item: LibraryShowItem) async {
        guard let next = item.progress.nextEpisode else { return }
        do {
            try await repository.addWatchEvent(for: MediaID(kind: .episode, id: next.tmdbID, traktID: next.traktID), watchedAt: Date())
            session.markLibraryUpdated(syncIfConnected: true)
            loadedRevision = nil
            await load(revision: session.libraryRevision)
        } catch {
            errorText = error.localizedDescription
        }
    }

    func markMovieWatched(_ item: LibraryMovieItem) async {
        do {
            try await repository.addWatchEvent(for: item.mediaID, watchedAt: Date())
            session.markLibraryUpdated(syncIfConnected: true)
            loadedRevision = nil
            await load(revision: session.libraryRevision)
        } catch {
            errorText = error.localizedDescription
        }
    }

    func stopWatching(_ item: LibraryShowItem) async {
        do {
            try await repository.setShowDisposition(.stopped, for: item.mediaID)
            session.markLibraryUpdated(syncIfConnected: true)
            loadedRevision = nil
            await load(revision: session.libraryRevision)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct WatchlistView: View {
    let kind: MediaKind
    let initialShowItems: [LibraryShowItem]
    let initialRevision: Int?

    @Environment(AppContainer.self) private var container
    @Environment(AppSession.self) private var session

    @State private var model: WatchlistScreenModel?
    @State private var detailRef: MediaID?
    @State private var episodeRef: EpisodeRef?

    init(
        kind: MediaKind,
        initialShowItems: [LibraryShowItem] = [],
        initialRevision: Int? = nil
    ) {
        self.kind = kind
        self.initialShowItems = initialShowItems
        self.initialRevision = initialRevision
    }

    var body: some View {
        Group {
            if let model {
                WatchlistBody(model: model, detailRef: $detailRef, episodeRef: $episodeRef)
            } else {
                ProgressView()
                    .task {
                        let newModel = WatchlistScreenModel(
                            kind: kind,
                            repository: container.libraryRepository,
                            session: session,
                            initialShowItems: initialShowItems,
                            initialRevision: initialRevision
                        )
                        model = newModel
                    }
            }
        }
        .sheet(item: $detailRef) { ref in
            NavigationStack {
                MediaDetailView(ref: ref, onClose: { detailRef = nil })
            }
        }
        .sheet(item: $episodeRef) { ref in
            NavigationStack {
                EpisodeView(ref: ref, onClose: { episodeRef = nil })
            }
        }
    }
}

private struct WatchlistBody: View {
    @Bindable var model: WatchlistScreenModel
    @Binding var detailRef: MediaID?
    @Binding var episodeRef: EpisodeRef?
    @Environment(AppSession.self) private var session

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        ScrollView {
            if model.isLoading {
                ProgressView().padding(.top, 60)
            } else if let errorText = model.errorText {
                ContentUnavailableView("Error",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(errorText))
            } else if model.kind == .movie, model.movieItems.isEmpty {
                ContentUnavailableView(
                    "Nothing to watch",
                    systemImage: "film",
                    description: Text("Add movies from Search to start tracking.")
                )
                .frame(maxWidth: .infinity, minHeight: 300)
                .padding(.top, 40)
            } else if model.kind == .show, model.showItems.isEmpty {
                ContentUnavailableView(
                    "You’re all caught up",
                    systemImage: "tv",
                    description: Text("No followed shows have a released unwatched episode.")
                )
                .frame(maxWidth: .infinity, minHeight: 300)
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: cols, spacing: 12) {
                    if model.kind == .movie {
                        ForEach(model.movieItems) { item in
                            MediaTile(
                                ref: item.mediaID,
                                title: item.title,
                                posterPath: item.posterPath,
                                showTitle: true,
                                selectedRef: $detailRef,
                                extraMenu: {
                                    Button {
                                        Haptics.notification(.success)
                                        Task { await model.markMovieWatched(item) }
                                    } label: {
                                        Label("Mark as Watched", systemImage: "checkmark.circle")
                                    }
                                    Divider()
                                }
                            )
                            .onTapGesture(count: 2) {
                                Haptics.notification(.success)
                                Task { await model.markMovieWatched(item) }
                            }
                            .frame(width: 110)
                        }
                    } else {
                        ForEach(model.showItems) { item in
                            let next = item.progress.nextEpisode
                            MediaTile(
                                ref: item.mediaID,
                                title: item.title,
                                posterPath: item.posterPath,
                                showTitle: true,
                                selectedRef: $detailRef,
                                onSelect: {
                                    episodeRef = next.map {
                                        EpisodeRef(
                                            showId: item.mediaID.tmdbID,
                                            showTraktID: item.mediaID.traktID,
                                            season: $0.season,
                                            episode: $0.episode,
                                            tmdbID: $0.tmdbID,
                                            traktID: $0.traktID
                                        )
                                    }
                                },
                                extraMenu: {
                                    Button { detailRef = item.mediaID } label: {
                                        Label("View Show", systemImage: "tv")
                                    }
                                    Divider()
                                    if let next = item.progress.nextEpisode {
                                        Button {
                                            Haptics.notification(.success)
                                            Task { await model.markNextEpisodeWatched(for: item) }
                                        } label: {
                                            Label("Mark S\(next.season) E\(next.episode) as Watched", systemImage: "checkmark.circle")
                                        }
                                    }
                                    Divider()
                                    Button {
                                        Haptics.notification(.success)
                                        Task { await model.stopWatching(item) }
                                    } label: {
                                        Label("Stop Watching", systemImage: "stop.circle")
                                    }
                                }
                            )
                            .accessibilityLabel(
                                next.map { "\(item.title), Season \($0.season) Episode \($0.episode), Continue Watching" }
                                    ?? item.title
                            )
                            .onTapGesture(count: 2) {
                                Haptics.notification(.success)
                                Task { await model.markNextEpisodeWatched(for: item) }
                            }
                            .overlay(alignment: .topLeading) {
                                if let next = item.progress.nextEpisode {
                                    Text("S\(next.season) E\(next.episode)")
                                        .font(.caption2.bold())
                                        .padding(3)
                                        .glassEffect()
                                        .padding(3)
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                if item.progress.remainingReleased > 0 {
                                    SystemBadge(label: "\(item.progress.remainingReleased)", color: .red, height: 20)
                                        .offset(x: 8, y: -8)
                                }
                            }
                            .frame(width: 110)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
            }
        }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.libraryRevision) {
            await model.load(revision: session.libraryRevision)
        }
    }
}
