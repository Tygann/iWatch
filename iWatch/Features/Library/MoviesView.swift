import SwiftUI
import Observation
import SwiftData

enum MovieSortOption: String, CaseIterable, Identifiable {
    case recentActivity
    case title
    case releaseDate

    var id: Self { self }

    var label: String {
        switch self {
        case .recentActivity: "Recent Activity"
        case .title: "Title"
        case .releaseDate: "Release Date"
        }
    }
}

enum MovieSortDirection: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: Self { self }
}

enum MovieLibrarySection {
    case watchlist
    case watched
}

enum MovieLibrarySorter {
    static func sort(
        _ items: [LibraryMovieItem],
        by option: MovieSortOption,
        direction: MovieSortDirection,
        section: MovieLibrarySection
    ) -> [LibraryMovieItem] {
        items.sorted { lhs, rhs in
            switch option {
            case .recentActivity:
                let lhsDate = activityDate(for: lhs, in: section)
                let rhsDate = activityDate(for: rhs, in: section)
                if lhsDate != rhsDate {
                    return ordered(lhsDate, before: rhsDate, direction: direction)
                }
            case .title:
                let comparison = lhs.title.localizedStandardCompare(rhs.title)
                if comparison != .orderedSame {
                    return direction == .ascending
                        ? comparison == .orderedAscending
                        : comparison == .orderedDescending
                }
            case .releaseDate:
                if lhs.releaseDate != rhs.releaseDate {
                    return orderedKnownDatesFirst(
                        lhs.releaseDate,
                        before: rhs.releaseDate,
                        direction: direction
                    )
                }
            }

            let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
            if titleComparison != .orderedSame {
                return titleComparison == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }

    private static func activityDate(
        for item: LibraryMovieItem,
        in section: MovieLibrarySection
    ) -> Date? {
        switch section {
        case .watchlist: item.listedAt
        case .watched: item.lastWatchedAt
        }
    }

    private static func ordered(
        _ lhs: Date?,
        before rhs: Date?,
        direction: MovieSortDirection
    ) -> Bool {
        orderedKnownDatesFirst(lhs, before: rhs, direction: direction)
    }

    private static func orderedKnownDatesFirst(
        _ lhs: Date?,
        before rhs: Date?,
        direction: MovieSortDirection
    ) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return direction == .ascending ? lhs < rhs : lhs > rhs
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return false
        }
    }
}

// MARK: - Movies State

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

// MARK: - Movies Screen

struct MoviesView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AppSession.self) private var session

    @State private var model: MoviesScreenModel?

    var body: some View {
        Group {
            if let model {
                MoviesViewBody(model: model)
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

// MARK: - Movies Content

private struct MoviesViewBody: View {
    @Bindable var model: MoviesScreenModel
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router

    @AppStorage("movieSortOption") private var sortOption = MovieSortOption.recentActivity
    @AppStorage("movieSortDirection") private var sortDirection = MovieSortDirection.descending

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    private var sortedWatchlistItems: [LibraryMovieItem] {
        MovieLibrarySorter.sort(
            model.watchlistItems,
            by: sortOption,
            direction: sortDirection,
            section: .watchlist
        )
    }

    private var sortedWatchedItems: [LibraryMovieItem] {
        MovieLibrarySorter.sort(
            model.watchedItems,
            by: sortOption,
            direction: sortDirection,
            section: .watched
        )
    }

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
                ToolbarItem(placement: .topBarTrailing) {
                    sortMenu
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.isShowingSettings = true } label: {
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
        }
    }

    @ViewBuilder
    // MARK: Library Sections

    private var sortMenu: some View {
        Menu {
            ForEach(MovieSortOption.allCases) { option in
                Button {
                    selectSortOption(option)
                } label: {
                    if option == sortOption {
                        Label {
                            Text("\(Text(option.label))\n\(Text(sortDirectionLabel).font(.caption).foregroundStyle(.secondary))")
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .accessibilityLabel("Sort Movies")
    }

    private var sortDirectionLabel: String {
        sortDirection == .ascending ? "Ascending" : "Descending"
    }

    private func selectSortOption(_ option: MovieSortOption) {
        if option == sortOption {
            sortDirection = sortDirection == .ascending ? .descending : .ascending
        } else {
            sortOption = option
        }
    }

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
                    ForEach(sortedWatchlistItems) { item in
                        movieTile(item, showTitle: true)
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
                    items: sortedWatchedItems,
                    showsReleaseYear: sortOption == .releaseDate,
                    markUnwatched: model.markUnwatched
                )
            } content: {
                ForEach(sortedWatchedItems.prefix(12)) { item in
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
        .overlay(alignment: .topTrailing) {
            if sortOption == .releaseDate, let releaseDate = item.releaseDate {
                Text(releaseDate.formatted(.dateTime.year()))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(3)
                    .glassEffect()
                    .padding(3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onTapGesture(count: 2) {
            Haptics.notification(.success)
            Task { await model.markWatched(item) }
        }
        .frame(width: 110)
    }
}

// MARK: - Collection Screen

private struct MovieCollectionView: View {
    let title: String
    let items: [LibraryMovieItem]
    let showsReleaseYear: Bool
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
                    .overlay(alignment: .topTrailing) {
                        if showsReleaseYear, let releaseDate = item.releaseDate {
                            Text(releaseDate.formatted(.dateTime.year()))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(3)
                                .glassEffect()
                                .padding(3)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
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

// MARK: - Previews

#Preview {
    let container = AppContainer.preview()
    MoviesView()
        .environment(container)
        .environment(container.session)
        .environment(container.router)
        .modelContainer(container.persistence.modelContainer)
}
