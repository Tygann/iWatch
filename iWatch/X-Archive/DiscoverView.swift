//import SwiftUI
//import SwiftData
//
//struct DiscoverView: View {
//    @EnvironmentObject private var env: AppEnvironment
//    
//    @State private var selected: ProgressItem?
//    @State private var showDetail = false
//    
//    // Search
//    @State private var query: String = ""
//    @State private var isSearching = false
//    @State private var resultsMixed: [SimpleDTO] = []
//
//    // Home shelves
//    @State private var trendingMovies: [SimpleDTO] = []
//    @State private var trendingTV: [SimpleDTO] = []
//    @State private var loadingHome = false
//    @State private var homeError: String?
//
//    enum Filter: String, CaseIterable, Identifiable {
//        case top = "Top Results"
//        case movies = "Movies"
//        case series = "Shows"
//        var id: String { rawValue }
//    }
//    @State private var filter: Filter = .top
//
//    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 12)]
//
//    var body: some View {
//        NavigationStack {
//            VStack(spacing: 0) {
//                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
//                    filterBar
//                        .padding(.horizontal)
//                        .padding(.top, 6)
//                }
//                content
//            }
//            .navigationTitle("Discover")
//            .searchable(
//                text: $query,
//                placement: .navigationBarDrawer(displayMode: .automatic),
//                prompt: "Search movies & TV"
//            )
//            .onChange(of: query) { _, _ in debounceSearch() }
//            .task { await loadHome() }
//            .sheet(isPresented: $showDetail) {
//                if let selected = selected {
//                    NavigationStack {
//                        ShowDetailView(progress: selected)
//                            .presentationBackground(.clear)
//                            .presentationDragIndicator(.visible)
//                            .toolbar {
//                                // Close Button
//                                ToolbarItem(placement: .topBarTrailing) {
//                                    Button(role: .close) {
//                                        showDetail = false
//                                    }
//                                }
//                            }
//                    }
//                }
//            }
//            
////            .sheet(item: $selected) { p in
////                NavigationStack {
////                    ShowDetailView(progress: p)
////                        .presentationBackground(.clear)
////                        .presentationDragIndicator(.visible)
////                        .toolbar {
////                            // Close Button
////                            ToolbarItem(placement: .topBarTrailing) {
////                                Button(role: .close) {
//////                                    showCardView = false
////                                }
////                            }
////                        }
////                }
////            }
//        }
//    }
//
//    // MARK: - UI Sections
//    private var filterBar: some View {
//        Picker("", selection: $filter) {
//            ForEach(Filter.allCases) { f in Text(f.rawValue).tag(f) }
//        }
//        .pickerStyle(.segmented)
//    }
//
//    @ViewBuilder
//    private var content: some View {
//        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
//            homeShelves
//        } else {
//            resultsGrid
//        }
//    }
//
//    private var homeShelves: some View {
//        Group {
//            if loadingHome {
//                LoadingView()
//            } else if let homeError {
//                ErrorView(message: homeError)
//            } else {
//                List {
//                    Section("Trending Movies") {
//                        grid(for: trendingMovies) { item in
//                            env.repository.addToWatchlist(simple: item, kind: .movie)
//                        }
//                        .listRowInsets(EdgeInsets())
//                    }
//                    Section("Trending TV") {
//                        grid(for: trendingTV) { item in
//                            env.repository.addToWatchlist(simple: item, kind: .tv)
//                        }
//                        .listRowInsets(EdgeInsets())
//                    }
//                }
//            }
//        }
//    }
//
//    // MARK: - Search Section
//    private var resultsGrid: some View {
//        Group {
//            if isSearching {
//                LoadingView().frame(maxWidth: .infinity, maxHeight: .infinity)
//            } else {
//                let items = filteredResults()
//                if items.isEmpty {
//                    ContentUnavailableView.search
//                } else {
//                    ScrollView {
//                        LazyVGrid(columns: cols, spacing: 12) {
//                            ForEach(items, id: \.id) { item in
////                                VStack(spacing: 6) {
//                                Button {
////                                    selected = item
//                                    showDetail = true
//                                } label: {
//                                    PosterImage(path: item.posterPath)
//                                        .frame(width: 110, height: 165)
//                                        .clipShape(RoundedRectangle(cornerRadius: 12))
//                                        .clipped()
////                                    Text(item.title)
////                                        .font(.caption)
////                                        .lineLimit(2)
////                                        .frame(width: 110, alignment: .leading)
//                                }
//                                .contentShape(Rectangle())
////                                .onTapGesture { selected = item }
////                                .onTapGesture {
//                                .contextMenu {
//                                    Button("Add to Watchlist") {
//                                        env.repository.addToWatchlist(simple: item, kind: item.kind)
//                                    }
//                                }
//                            }
//                        }
//                        .padding(.horizontal, 12)
//                        .padding(.top, 12)
//                    }
//                }
//            }
//        }
//    }
//    
//    // MARK: - Discover Section
//    // Reusable grid builder for a [SimpleDTO] shelf inside List sections
//    private func grid(for items: [SimpleDTO], onTap: @escaping (SimpleDTO) -> Void) -> some View {
////    private var grid: some View {
//        ScrollView(.horizontal, showsIndicators: false) {
//            HStack(spacing: 12) {
//                ForEach(items, id: \.id) { item in
////                    VStack(spacing: 6) {
//                    Button {
////                        selected = item
//                        showDetail = true
//                    } label: {
//                        PosterImage(path: item.posterPath)
//                            .frame(width: 110, height: 165)
//                            .clipShape(RoundedRectangle(cornerRadius: 12))
//                            .clipped()
////                        Text(item.title)
////                            .font(.caption)
////                            .lineLimit(2)
////                            .frame(width: 110, alignment: .leading)
//                    }
//                    .contentShape(Rectangle())
////                    .onTapGesture { onTap(item) }
////                    .contextMenu {
////                        Button("Add to Watchlist") {
////                            env.repository.addToWatchlist(simple: item, kind: item.kind)
////                        }
////                    }
//                }
//            }
//            .padding(.horizontal, 12)
//            .padding(.vertical, 8)
//        }
//    }
//
//    // MARK: - Filtering
//
//    private func filteredResults() -> [SimpleDTO] {
//        switch filter {
//        case .top:    return resultsMixed
//        case .movies: return resultsMixed.filter { $0.kind == .movie }
//        case .series: return resultsMixed.filter { $0.kind == .tv }
//        }
//    }
//
//    // MARK: - Actions
//
//    private func debounceSearch() {
//        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
//        guard !trimmed.isEmpty else {
//            isSearching = false
//            resultsMixed = []
//            return
//        }
//        Task {
//            try? await Task.sleep(nanoseconds: 350_000_000)
//            guard trimmed == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
//            await performSearch(trimmed)
//        }
//    }
//
//    @MainActor
//    private func performSearch(_ q: String) async {
//        isSearching = true
//        defer { isSearching = false }
//        do {
//            let res = try await env.contentAPI.search(query: q, page: 1)
//            resultsMixed = res.compactMap { $0.simple }
//        } catch {
//            resultsMixed = []
//        }
//    }
//
//    @MainActor
//    private func loadHome() async {
//        loadingHome = true
//        homeError = nil
//        async let m = env.contentAPI.trendingMovies(page: 1)
//        async let t = env.contentAPI.trendingTV(page: 1)
//        do {
//            let (mm, tt) = try await (m, t)
//            trendingMovies = mm.map(\.simple)
//            trendingTV = tt.map(\.simple)
//            loadingHome = false
//        } catch {
//            loadingHome = false
//            homeError = "Failed to load trending content."
//        }
//    }
//}
//
//#Preview {
//    // In-memory SwiftData container for previews
//    let schema = Schema([MediaItem.self, ProgressItem.self])
//    let config = ModelConfiguration(isStoredInMemoryOnly: true)
//    let container = try! ModelContainer(for: schema, configurations: [config])
//
////    // Preview environment object
////    let env = AppEnvironment(modelContainer: container, contentAPI: MockAPI())
//    
//    // Load your actual TMDB key from Secrets.plist
//    let env = AppEnvironment(
//        modelContainer: container,
//        contentAPI: TMDBClient(apiKey: Secrets.tmdbAPIKey)
//    )
//
//    return DiscoverView()
//        .environmentObject(env)
//        .modelContainer(container)
//}
