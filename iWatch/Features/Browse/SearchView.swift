import SwiftUI
import Observation

private enum SearchMediaScope: String, CaseIterable, Identifiable {
    case all = "All"
    case movies = "Movies"
    case shows = "Shows"

    var id: String { rawValue }

    func filter(_ items: [SearchItem]) -> [SearchItem] {
        switch self {
        case .all: items
        case .movies: items.filter { $0.kind == .movie }
        case .shows: items.filter { $0.kind == .show }
        }
    }
}

@MainActor
@Observable
private final class SearchScreenModel {
    private let repository: LibraryRepository
    private var searchTask: Task<Void, Never>?

    var query = ""
    var isSearching = false
    var results: [SearchItem] = []
    var trending: [SearchItem] = []
    var providers: [DiscoveryProvider] = []
    var selectedFilter: SearchMediaScope = .all
    var errorText: String?

    let regionCode: String

    init(repository: LibraryRepository, regionCode: String) {
        self.repository = repository
        self.regionCode = regionCode
    }

    func bootstrap() async {
        guard trending.isEmpty && providers.isEmpty else { return }
        async let loadedTrending = try? repository.mixedTrending()
        async let loadedProviders = try? repository.watchProviders(regionCode: regionCode)
        trending = await loadedTrending ?? []
        providers = await loadedProviders ?? []
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

    var filteredResults: [SearchItem] {
        selectedFilter.filter(results)
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
                        let newModel = SearchScreenModel(
                            repository: container.libraryRepository,
                            regionCode: Locale.current.region?.identifier ?? "US"
                        )
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

    private let featuredStreamingProviderIDs: [Int] = [
        8,    // Netflix
        350,  // Apple TV+
        337,  // Disney+
        9,    // Amazon Prime Video
        15,   // Hulu
        1899, // Max
        386,  // Peacock
        531,  // Paramount+
        73,   // Tubi
        300,  // Pluto TV
        207,  // The Roku Channel
        283   // Crunchyroll
    ]

    var body: some View {
        NavigationStack {
            Group {
                if model.query.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            trendingSection

                            providerSection

                            VStack(alignment: .leading, spacing: 12) {
                                Text("Browse")
                                    .font(.title2.bold())
                                    .padding(.horizontal)

                                BrowseGrid()
                                    .padding(.horizontal)
                            }
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
        if !model.trending.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                trendingLink(items: model.trending)
                .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(model.trending) { item in
                            DiscoveryPosterTile(item: item, showTitle: false, showKindBadge: true)
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
            ScopedDiscoveryGrid(title: "Trending", items: items)
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

    @ViewBuilder private var providerSection: some View {
        if !model.providers.isEmpty {
            let providersByID = Dictionary(uniqueKeysWithValues: model.providers.map { ($0.id, $0) })
            let featuredProviders = featuredStreamingProviderIDs.compactMap { providersByID[$0] }
            let previewProviders = featuredProviders.isEmpty
                ? Array(model.providers.prefix(10))
                : featuredProviders

            VStack(alignment: .leading, spacing: 4) {
                NavigationLink {
                    ProviderBrowseView(initialKind: .movie)
                } label: {
                    HStack(spacing: 6) {
                        Text("Services")
                            .font(.title3.bold())
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.callout.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(previewProviders) { provider in
                            NavigationLink {
                                ProviderResultsView(
                                    provider: provider,
                                    initialKind: .movie,
                                    regionCode: model.regionCode
                                )
                            } label: {
                                CompactProviderLogo(provider: provider)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        VStack(spacing: 16) {
            Picker("Filter", selection: $model.selectedFilter) {
                ForEach(SearchMediaScope.allCases) { filter in
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                        ForEach(model.filteredResults) { item in
                            DiscoveryPosterTile(
                                item: item,
                                showTitle: true,
                                showKindBadge: model.selectedFilter == .all
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                }
            }
        }
    }
}

private struct DiscoveryPosterTile: View {
    let item: SearchItem
    let showTitle: Bool
    let showKindBadge: Bool

    var body: some View {
        MediaTile(
            ref: item.mediaID,
            title: item.title,
            posterPath: item.posterPath,
            showTitle: showTitle
        )
        .accessibilityLabel(accessibilityLabel)
        .overlay(alignment: .topLeading) {
            if showKindBadge {
                Image(systemName: item.kind == .movie ? "film.fill" : "tv.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(item.kind == .movie ? .purple : .blue)
                    .frame(width: 12, height: 12)
                    .padding(3)
                    .glassEffect(.regular, in: .circle)
                    .padding(3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let year = item.year {
                Text(year)
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

    private var accessibilityLabel: String {
        [item.title, item.kind == .movie ? "Movie" : "Show", item.year]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

private struct CompactProviderLogo: View {
    let provider: DiscoveryProvider

    var body: some View {
        ServiceProviderTile(
            name: provider.name,
            logoPath: provider.logoPath,
            size: 64,
            caption: nil
        )
    }
}

private struct ScopedDiscoveryGrid: View {
    let title: String
    let items: [SearchItem]

    @State private var scope: SearchMediaScope = .all
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        VStack(spacing: 12) {
            Picker("Filter", selection: $scope) {
                ForEach(SearchMediaScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(scope.filter(items)) { item in
                        DiscoveryPosterTile(
                            item: item,
                            showTitle: true,
                            showKindBadge: scope == .all
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
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
