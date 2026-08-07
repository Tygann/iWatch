import SwiftUI
import Observation

@MainActor
@Observable
private final class SearchScreenModel {
    enum Filter: String, CaseIterable, Identifiable {
        case top = "All"
        case movies = "Movies"
        case shows = "Shows"

        var id: String { rawValue }
    }

    private let repository: LibraryRepository
    private var searchTask: Task<Void, Never>?

    var query = ""
    var isSearching = false
    var results: [SearchItem] = []
    var movieTrending: [SearchItem] = []
    var showTrending: [SearchItem] = []
    var selectedFilter: Filter = .top
    var errorText: String?

    init(repository: LibraryRepository) {
        self.repository = repository
    }

    func bootstrap() async {
        guard movieTrending.isEmpty && showTrending.isEmpty else { return }
        await loadTrending()
    }

    func updateQuery(_ newValue: String) {
        query = newValue
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.performSearch()
        }
    }

    func performSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            errorText = nil
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            results = try await repository.search(query: trimmed)
            errorText = nil
        } catch {
            guard !error.isCancelled else { return }
            results = []
            errorText = error.localizedDescription
        }
    }

    func loadTrending() async {
        do {
            async let movies = repository.trending(kind: .movie)
            async let shows = repository.trending(kind: .show)
            movieTrending = try await movies
            showTrending = try await shows
            errorText = nil
        } catch {
            guard !error.isCancelled else { return }
            errorText = error.localizedDescription
        }
    }

    var filteredResults: [SearchItem] {
        switch selectedFilter {
        case .top:
            return results
        case .movies:
            return results.filter { $0.kind == .movie }
        case .shows:
            return results.filter { $0.kind == .show }
        }
    }
}

struct SearchView: View {
    @Environment(AppContainer.self) private var container

    @State private var model: SearchScreenModel?
    @State private var showSettings = false

    var body: some View {
        Group {
            if let model {
                SearchViewBody(
                    model: model,
                    showSettings: $showSettings
                )
            } else {
                ProgressView()
                    .task {
                        let newModel = SearchScreenModel(repository: container.libraryRepository)
                        await newModel.bootstrap()
                        guard !Task.isCancelled else { return }
                        model = newModel
                    }
            }
        }
    }
}

private struct SearchViewBody: View {
    @Bindable var model: SearchScreenModel
    @Binding var showSettings: Bool
    @State private var trendingKind = MediaKind.movie

    var body: some View {
        NavigationStack {
            Group {
                if model.query.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            trendingSection

                            VStack(alignment: .leading, spacing: 12) {
                                Text("Browse")
                                    .font(.title2.bold())
                                    .padding(.horizontal)

                                BrowseGrid()
                                    .padding(.horizontal)
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                Text("Streaming Services")
                                    .font(.title2.bold())

                                BrowseByServiceLink(kind: nil)
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 16)
                        }
                        .padding(.top, 8)
                    }
                } else {
                    resultsSection
                }
            }
            .navigationTitle("Search")
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
        }
        .searchable(
            text: Binding(
                get: { model.query },
                set: { model.updateQuery($0) }
            ),
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Movies and TV Shows"
        )
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

    @ViewBuilder private var trendingSection: some View {
        let items = trendingKind == .movie ? model.movieTrending : model.showTrending
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        trendingLink(items: items)

                        Spacer()

                        trendingPicker
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        trendingLink(items: items)
                        trendingPicker
                    }
                }
                .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(items) { item in
                            MediaTile(ref: item.mediaID, title: item.title, posterPath: item.posterPath, showTitle: false)
                                .frame(width: 110)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
            .padding(.top, 12)
        }
    }

    private func trendingLink(items: [SearchItem]) -> some View {
        NavigationLink {
            SearchCollectionView(title: "Trending", items: items)
        } label: {
            HStack(spacing: 6) {
                Text("Trending")
                    .font(.title3.bold())
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.callout.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var trendingPicker: some View {
        Picker("Trending Media Type", selection: $trendingKind) {
            Image(systemName: "film").tag(MediaKind.movie)
            Image(systemName: "tv").tag(MediaKind.show)
        }
        .pickerStyle(.segmented)
        .frame(width: 104)
    }

    @ViewBuilder
    private var resultsSection: some View {
        VStack(spacing: 16) {
            Picker("Filter", selection: $model.selectedFilter) {
                ForEach(SearchScreenModel.Filter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if model.isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText = model.errorText {
                ContentUnavailableView("Search Error",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(errorText))
            } else if model.filteredResults.isEmpty {
                ContentUnavailableView("No Results",
                                       systemImage: "magnifyingglass",
                                       description: Text("Try a different title or keyword."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.filteredResults) { item in
                            SearchResultRow(item: item)

                            Divider()
                                .padding(.leading, 92)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

private struct SearchResultRow: View {
    let item: SearchItem

    var body: some View {
        NavigationLink {
            MediaDetailView(ref: item.mediaID)
        } label: {
            HStack(spacing: 14) {
                PosterImage(path: item.posterPath, width: 64, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        Label(item.kind == .movie ? "Movie" : "Show", systemImage: item.kind == .movie ? "film" : "tv")
                            .foregroundStyle(item.kind == .movie ? .purple : .blue)

                        if let year = item.year {
                            Text(year)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            WatchlistMenu(ref: item.mediaID, title: item.title, posterPath: item.posterPath)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SearchCollectionView: View {
    let title: String
    let items: [SearchItem]

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(items) { item in
                    MediaTile(
                        ref: item.mediaID,
                        title: item.title,
                        posterPath: item.posterPath,
                        showTitle: true
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

private struct BrowseGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            [GridItem(.flexible())]
        } else {
            [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        }
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            NavigationLink { BrowseCategoryView(kind: .movie) } label: {
                AppStoreCategoryButton(
                    title: "Movies",
                    symbol: "film",
                    gradient: .appStorePurple
                )
            }
            NavigationLink { BrowseCategoryView(kind: .show) } label: {
                AppStoreCategoryButton(
                    title: "Shows",
                    symbol: "tv",
                    gradient: .appStoreBlue
                )
            }
        }
        .buttonStyle(.plain)
    }
}

private struct AppStoreCategoryButton: View {
    let title: String
    let symbol: String
    let gradient: LinearGradient

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(gradient)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .white.opacity(0.15), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.plusLighter)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
                .blendMode(.overlay)

            HStack(alignment: .center) {
                VStack(alignment: .leading) {
                    Spacer(minLength: 0)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                }

                Spacer(minLength: 0)

                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            }
            .padding(16)
        }
        .frame(height: 110)
    }
}

private extension LinearGradient {
    static let appStorePurple = LinearGradient(
        colors: [Color(red: 0.55, green: 0.30, blue: 0.96), Color(red: 0.78, green: 0.35, blue: 0.93)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let appStoreBlue = LinearGradient(
        colors: [Color(red: 0.17, green: 0.53, blue: 0.96), Color(red: 0.26, green: 0.78, blue: 0.94)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
