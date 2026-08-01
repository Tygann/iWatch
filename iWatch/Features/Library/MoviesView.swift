import SwiftUI
import Observation
import SwiftData

@MainActor
@Observable
private final class MoviesScreenModel {
    enum Segment: String, CaseIterable, Identifiable {
        case following = "Following"
        case toWatch = "To Watch"

        var id: String { rawValue }
    }

    private let repository: LibraryRepository
    private let session: AppSession

    var items: [LibraryMovieItem] = []
    var isLoading = false
    var isEnriching = false
    var errorText: String?
    var segment: Segment = .following

    init(repository: LibraryRepository, session: AppSession) {
        self.repository = repository
        self.session = session
    }

    func load(revision: Int, forceRefresh: Bool = false) async {
        let shouldShowLoading = items.isEmpty
        if shouldShowLoading { isLoading = true }
        defer { isLoading = false }

        do {
            items = try await repository.movieLibraryItems(revision: revision, forceRefresh: forceRefresh)
            errorText = nil
        } catch {
            guard !error.isCancelled else { return }
            errorText = error.localizedDescription
            items = []
        }
    }

    func enrichMissingMetadata() async {
        guard !isEnriching else { return }
        isEnriching = true
        defer { isEnriching = false }

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

    var filteredItems: [LibraryMovieItem] {
        switch segment {
        case .following:
            return items
        case .toWatch:
            return items.filter { !$0.isWatched }
        }
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
    @State private var detailRef: MediaID?

    var body: some View {
        Group {
            if let model {
                MoviesViewBody(
                    model: model,
                    detailRef: $detailRef,
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
    @Binding var detailRef: MediaID?
    @Binding var showSettings: Bool
    @Environment(AppSession.self) private var session

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Section", selection: $model.segment) {
                    ForEach(MoviesScreenModel.Segment.allCases) { segment in
                        Text(segment.rawValue).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if model.isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if let errorText = model.errorText {
                    ContentUnavailableView("Movies Error",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(errorText))
                } else if model.filteredItems.isEmpty {
                    ContentUnavailableView(
                        model.segment == .following ? "No followed movies yet" : "Nothing to watch",
                        systemImage: "film",
                        description: Text(model.segment == .following
                                          ? "Add movies from Search to start tracking."
                                          : "You’re all caught up on the movies you follow.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(model.filteredItems) { item in
                                MediaTile(
                                    ref: item.mediaID,
                                    title: item.title,
                                    posterPath: item.posterPath,
                                    showTitle: true,
                                    selectedRef: $detailRef
                                ) {
                                    if item.isWatched {
                                        Button("Mark as Unwatched") {
                                            Haptics.notification(.success)
                                            Task { await model.markUnwatched(item) }
                                        }
                                    } else {
                                        Button("Mark as Watched") {
                                            Haptics.notification(.success)
                                            Task { await model.markWatched(item) }
                                        }
                                    }
                                }
                                .frame(width: 110)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
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
}

#Preview {
    let container = AppContainer.preview()
    MoviesView()
        .environment(container)
        .environment(container.session)
        .environment(container.router)
        .modelContainer(container.persistence.modelContainer)
}
