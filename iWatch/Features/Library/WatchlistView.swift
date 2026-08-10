import SwiftUI
import Observation
import SwiftData

// MARK: - Watchlist State

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

    func markNextEpisodeWatched(for item: LibraryShowItem, showsFeedback: Bool = false) async {
        guard let next = item.progress.nextEpisode else { return }
        do {
            try await repository.addWatchEvent(for: MediaID(kind: .episode, id: next.tmdbID, traktID: next.traktID), watchedAt: Date())
            if showsFeedback {
                session.showEpisodeWatchSuccess(
                    showTitle: item.title,
                    season: next.season,
                    episode: next.episode
                )
            }
            session.markLibraryUpdated(syncIfConnected: true)
            loadedRevision = nil
            await load(revision: session.libraryRevision)
        } catch {
            errorText = error.localizedDescription
        }
    }

    func markMovieWatched(_ item: LibraryMovieItem, showsFeedback: Bool = false) async {
        do {
            try await repository.addWatchEvent(for: item.mediaID, watchedAt: Date())
            if showsFeedback {
                session.showMovieWatchSuccess(title: item.title, isRewatch: item.isWatched)
            }
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

// MARK: - Watchlist Screen

struct WatchlistView: View {
    let kind: MediaKind
    let initialShowItems: [LibraryShowItem]
    let initialRevision: Int?

    @Environment(AppContainer.self) private var container
    @Environment(AppSession.self) private var session

    @State private var model: WatchlistScreenModel?

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
                WatchlistBody(model: model)
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
    }
}

// MARK: - Watchlist Content

private struct WatchlistBody: View {
    @Bindable var model: WatchlistScreenModel
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
                                Task { await model.markMovieWatched(item, showsFeedback: true) }
                            }
                            .frame(width: 110)
                        }
                    } else {
                        ForEach(model.showItems) { item in
                            continueWatchingTile(item)
                            .accessibilityLabel(
                                item.progress.nextEpisode.map { "\(item.title), Season \($0.season) Episode \($0.episode), Continue Watching" }
                                    ?? item.title
                            )
                            .onTapGesture(count: 2) {
                                Task { await model.markNextEpisodeWatched(for: item, showsFeedback: true) }
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

    // MARK: Show Actions

    @ViewBuilder
    private func continueWatchingTile(_ item: LibraryShowItem) -> some View {
        if let next = item.progress.nextEpisode {
            let episodeRef = EpisodeRef(
                showId: item.mediaID.tmdbID,
                showTraktID: item.mediaID.traktID,
                season: next.season,
                episode: next.episode,
                tmdbID: next.tmdbID,
                traktID: next.traktID
            )

            MediaTile(
                ref: item.mediaID,
                title: item.title,
                posterPath: item.posterPath,
                showTitle: true,
                transitionID: .episode(episodeRef),
                destination: { EpisodeView(ref: episodeRef) },
                extraMenu: { continueWatchingMenu(for: item) }
            )
        } else {
            MediaTile(
                ref: item.mediaID,
                title: item.title,
                posterPath: item.posterPath,
                showTitle: true,
                extraMenu: { continueWatchingMenu(for: item) }
            )
        }
    }

    @ViewBuilder
    private func continueWatchingMenu(for item: LibraryShowItem) -> some View {
        NavigationLink {
            MediaDetailView(ref: item.mediaID)
        } label: {
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
}

// MARK: - Previews

#Preview("Movie Watchlist") {
    WatchlistPreview(mode: .movies)
}

#Preview("Continue Watching") {
    WatchlistPreview(mode: .shows)
}

#Preview("Empty Watchlist") {
    WatchlistPreview(mode: .empty)
}

// MARK: - Preview Support

private enum WatchlistPreviewFixtures {
    static let movies = [
        LibraryMovieItem(
            mediaID: MediaID(kind: .movie, id: 401),
            title: "The Long Way Home",
            posterPath: nil,
            releaseDate: .now,
            listedAt: .now,
            isInWatchlist: true,
            playCount: 0,
            lastWatchedAt: nil
        ),
        LibraryMovieItem(
            mediaID: MediaID(kind: .movie, id: 402),
            title: "Midnight Signal",
            posterPath: nil,
            releaseDate: .now,
            listedAt: .now,
            isInWatchlist: true,
            playCount: 0,
            lastWatchedAt: nil
        )
    ]

    static let shows = [
        show(id: 501, title: "Northern Lights", season: 2, episode: 4, remaining: 3),
        show(id: 502, title: "Foundation", season: 1, episode: 8, remaining: 1)
    ]

    private static func show(
        id: Int,
        title: String,
        season: Int,
        episode: Int,
        remaining: Int
    ) -> LibraryShowItem {
        LibraryShowItem(
            mediaID: MediaID(kind: .show, id: id),
            title: title,
            posterPath: nil,
            status: ShowStatusSnapshot(bucket: .airing, nextAirDate: .now),
            progress: ShowProgress(
                watchedEpisodeKeys: [],
                watchedCount: episode - 1,
                totalEpisodes: episode + remaining,
                remainingReleased: remaining,
                nextEpisode: ShowProgress.NextEpisode(
                    tmdbID: id * 10,
                    traktID: nil,
                    season: season,
                    episode: episode,
                    airDate: .now,
                    airedAt: nil
                )
            ),
            isInWatchlist: true,
            disposition: .active,
            listedAt: .now,
            lastWatchedAt: .now,
            needsProgressEnrichment: false
        )
    }
}

private struct WatchlistPreview: View {
    enum Mode: Equatable {
        case movies
        case shows
        case empty
    }

    private let container: AppContainer
    @State private var model: WatchlistScreenModel

    init(mode: Mode) {
        let container = AppContainer.preview()
        let kind: MediaKind = mode == .shows ? .show : .movie
        let model = WatchlistScreenModel(
            kind: kind,
            repository: container.libraryRepository,
            session: container.session,
            initialShowItems: mode == .shows ? WatchlistPreviewFixtures.shows : [],
            initialRevision: container.session.libraryRevision
        )
        if mode == .movies {
            model.movieItems = WatchlistPreviewFixtures.movies
        }
        self.container = container
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            WatchlistBody(model: model)
        }
        .environment(container)
        .environment(container.session)
        .environment(container.router)
        .modelContainer(container.persistence.modelContainer)
    }
}
