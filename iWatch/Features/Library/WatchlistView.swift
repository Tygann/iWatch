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

    init(kind: MediaKind, repository: LibraryRepository, session: AppSession) {
        self.kind = kind
        self.repository = repository
        self.session = session
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if kind == .movie {
                movieItems = try await repository.movieLibraryItems().filter { !$0.isWatched }
            } else {
                showItems = try await repository.showLibraryItems()
                    .filter { $0.progress.remainingReleased > 0 }
            }
            errorText = nil
        } catch {
            guard !error.isCancelled else { return }
            errorText = error.localizedDescription
        }
    }

    var title: String { kind == .movie ? "To Watch" : "Continue Watching" }

    func markNextEpisodeWatched(for item: LibraryShowItem) async {
        guard let next = item.progress.nextEpisode else { return }
        do {
            try await repository.addWatchEvent(for: MediaID(kind: .episode, id: next.tmdbID, traktID: next.traktID), watchedAt: Date())
            session.markLibraryUpdated(syncIfConnected: true)
            await load()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct WatchlistView: View {
    let kind: MediaKind

    @Environment(AppContainer.self) private var container
    @Environment(AppSession.self) private var session

    @State private var model: WatchlistScreenModel?
    @State private var detailRef: MediaID?

    var body: some View {
        Group {
            if let model {
                WatchlistBody(model: model, detailRef: $detailRef)
            } else {
                ProgressView()
                    .task {
                        let newModel = WatchlistScreenModel(kind: kind, repository: container.libraryRepository, session: session)
                        await newModel.load()
                        guard !Task.isCancelled else { return }
                        model = newModel
                    }
            }
        }
        .sheet(item: $detailRef) { ref in
            NavigationStack {
                MediaDetailView(ref: ref)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(role: .close) { detailRef = nil }
                        }
                    }
            }
        }
    }
}

private struct WatchlistBody: View {
    @Bindable var model: WatchlistScreenModel
    @Binding var detailRef: MediaID?
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
                                selectedRef: $detailRef
                            )
                            .frame(width: 110)
                        }
                    } else {
                        ForEach(model.showItems) { item in
                            MediaTile(
                                ref: item.mediaID,
                                title: item.title,
                                posterPath: item.posterPath,
                                showTitle: true,
                                selectedRef: $detailRef
                            ) {
                                if item.progress.nextEpisode != nil {
                                    Button {
                                        Haptics.notification(.success)
                                        Task { await model.markNextEpisodeWatched(for: item) }
                                    } label: {
                                        Label("Mark as Watched", systemImage: "rectangle.badge.checkmark")
                                    }
                                }
                            }
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
            await model.load()
        }
    }
}
