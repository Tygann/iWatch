import SwiftUI
import SwiftData
import Combine

struct SearchView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.modelContext) private var modelContext
    @StateObject private var suggestionsHolder = SuggestionsHolder()

    // Search state
    @State private var query: String = ""
    @State private var isSearching = false
    @State private var results: [SimpleDTO] = []
    @State private var selectedFilter: Filter = .top

    // Sheet selection for MediaDetailView
    @State private var detailRef: MediaRef? = nil

    @State private var showSettings = false
    
    enum Filter: String, CaseIterable, Identifiable {
        case top = "Top Results"
        case movies = "Movies"
        case shows = "Shows"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            // Suggested / Trending
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Suggested")
                                    .font(.title2).bold()
                                    .padding(.horizontal)
                                
                                if let s = store {
                                    SuggestedSection(store: s, selectedRef: $detailRef)
                                        .padding(.horizontal)
                                } else {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding(.horizontal)
                                }
                            }
                            
                            // Browse
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Browse")
                                    .font(.title2.bold())
                                    .padding(.horizontal)
                                
                                BrowseGrid()
                                    .padding(.horizontal)
                                    .padding(.bottom, 8)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .onAppear {
                        suggestionsHolder.ensureStore(env: env, modelContext: modelContext)
                    }
                    .refreshable {
                        await store?.refresh()
                    }
                } else {
                    // ----- Search Results -----
                    SearchResultsSection(
                        query: query,
                        selectedFilter: $selectedFilter,
                        isSearching: $isSearching,
                        results: $results,
                        selectedRef: $detailRef      // <- pass the binding down
                    )
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
                }
            }
        }
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Movies and TV Shows"
        )
        .onChange(of: query) { _, _ in
            Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                await performSearch()
            }
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
        
        // Single sheet presenter for detail
        .sheet(item: $detailRef) { ref in
            NavigationStack {
                MediaDetailView(ref: ref)
                    .presentationDragIndicator(.visible)
//                    .presentationDetents([.medium, .large])
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(role: .close) { detailRef = nil }
                        }
                    }
            }
        }
    }

    // MARK: - Search
    @MainActor
    private func performSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = []; isSearching = false; return }
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await env.contentAPI.search(query: q, page: 1)
        } catch {
            results = []
            #if DEBUG
            print("Search failed:", error)
            #endif
        }
    }
}

// MARK: - Browse Grid (Movies / Shows)
private struct BrowseGrid: View {
    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            NavigationLink { BrowseCategoryView(kind: .movie) } label: {
                AppStoreCategoryButton(
                    title: "Movies",
                    symbol: "film",
                    gradient: .appStorePurple
                )
            }
            NavigationLink { BrowseCategoryView(kind: .tv) } label: {
                AppStoreCategoryButton(
                    title: "Shows",
                    symbol: "tv",
                    gradient: .appStoreBlue
                )
            }
        }
        .buttonStyle(.plain) // keep the card look on tap
    }
}

/// A rounded, glossy, gradient tile that mimics the App Store category cards.
private struct AppStoreCategoryButton: View {
    let title: String
    let symbol: String
    let gradient: LinearGradient

    var body: some View {
        ZStack {
            // Card background
//            RoundedRectangle(cornerRadius: 24, style: .continuous)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(gradient)

            // Subtle top gloss
//            RoundedRectangle(cornerRadius: 24, style: .continuous)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.35),
                            .white.opacity(0.15),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.plusLighter)

            // Thin inner stroke for that “pressed” look
//            RoundedRectangle(cornerRadius: 24, style: .continuous)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
                .blendMode(.overlay)

            // Content
            HStack(alignment: .center) {
                // Left-aligned title (white, large, bold)
                VStack(alignment: .leading) {
                    Spacer(minLength: 0)
                    Text(title)
//                        .font(.system(size: 28, weight: .bold))
                        .font(.headline)
//                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                }

                Spacer(minLength: 0)

                // Right badge with symbol (like App Store 3D sticker)
                ZStack {
//                    RoundedRectangle(cornerRadius: 16, style: .continuous)
//                        .fill(.white.opacity(0.95))
//                        .frame(width: 68, height: 68)
//                        .shadow(color: .black.opacity(0.25), radius: 10, y: 8)

                    Image(systemName: symbol)
                        .font(.system(size: 40, weight: .semibold))
//                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.secondary)
//                        .foregroundStyle(.black.opacity(0.8))
                }
//                .rotationEffect(.degrees(-2))          // tiny playful tilt
//                .offset(y: 4)                           // sits slightly low like Apple’s
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .shadow(color: .black.opacity(0.28), radius: 16, y: 10) // card drop shadow
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - Gradients tuned to the App Store vibe
private extension LinearGradient {
    static let appStoreBlue = LinearGradient(
        colors: [
            Color(red: 0.64, green: 0.84, blue: 1.00), // light sky blue
            Color(red: 0.38, green: 0.64, blue: 1.00)  // richer blue
        ],
        startPoint: .top, endPoint: .bottom
    )

    static let appStoreIndigo = LinearGradient(
        colors: [
            Color(red: 0.74, green: 0.76, blue: 1.00),
            Color(red: 0.50, green: 0.60, blue: 1.00)
        ],
        startPoint: .top, endPoint: .bottom
    )

    static let appStorePurple = LinearGradient(
        colors: [
            Color(red: 0.78, green: 0.66, blue: 1.00),
            Color(red: 0.56, green: 0.34, blue: 0.94)
        ],
        startPoint: .top, endPoint: .bottom
    )

    static let appStoreGreen = LinearGradient(
        colors: [
            Color(red: 0.70, green: 0.95, blue: 0.75),
            Color(red: 0.30, green: 0.75, blue: 0.50)
        ],
        startPoint: .top, endPoint: .bottom
    )

    static let appStoreOrange = LinearGradient(
        colors: [
            Color(red: 1.00, green: 0.78, blue: 0.55),
            Color(red: 1.00, green: 0.55, blue: 0.15)
        ],
        startPoint: .top, endPoint: .bottom
    )

    static let appStoreRed = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.45, blue: 0.45),
            Color(red: 0.95, green: 0.25, blue: 0.25)
        ],
        startPoint: .top, endPoint: .bottom
    )
}

// MARK: - Search Results Section
private struct SearchResultsSection: View {
    let query: String
    @Binding var selectedFilter: SearchView.Filter
    @Binding var isSearching: Bool
    @Binding var results: [SimpleDTO]

    // binding to the parent's sheet selection
    @Binding var selectedRef: MediaRef?

    private let grid = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    private var filtered: [SimpleDTO] {
        switch selectedFilter {
        case .top:    return results
        case .movies: return results.filter { $0.kind == .movie }
        case .shows:  return results.filter { $0.kind == .tv }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            if isSearching {
                ProgressView().padding(.top, 24)
                Spacer()
            } else if filtered.isEmpty {
                ContentUnavailableView("No Results", systemImage: "magnifyingglass", description: Text("Try a different search."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: grid, spacing: 12) {
                        ForEach(filtered, id: \.id) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                MediaTile(
                                    ref: .init(id: item.id, kind: item.kind),
                                    title: item.title,
                                    posterPath: item.posterPath,
                                    showTitle: true,              // shows the title under the poster
                                    selectedRef: $selectedRef     // <-- tap opens the sheet
                                )
                                
                                HStack {
                                    // Optional: Release date
                                    if let year = item.year {
                                        Text(String(year))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    // Optional: Media type
                                    if selectedFilter == .top {
//                                        Text("•")
//                                            .foregroundStyle(.secondary)
                                        
                                        if item.kind == .movie {
                                            Text("Movie")
                                                .font(.caption)
                                                .foregroundStyle(.purple)
                                        }
                                        
                                        if item.kind == .tv {
                                            Text("TV Show")
                                                .font(.caption)
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                            }
                            .frame(width: 110) // keeps a consistent grid width
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
        }
        .animation(.easeInOut, value: isSearching)
        .animation(.easeInOut, value: results)
        .safeAreaBar(edge: .top) {
            Picker("", selection: $selectedFilter) {
                ForEach(SearchView.Filter.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
        }
    }
}

// MARK: - Suggested Section
private struct SuggestedSection: View {
    @ObservedObject var store: SuggestionsStore
    @Binding var selectedRef: MediaRef?

    var body: some View {
        Group {
            if store.isLoading && store.suggested.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if let err = store.errorText, store.suggested.isEmpty {
                ContentUnavailableView(
                    "Couldn’t load suggestions",
                    systemImage: "exclamationmark.triangle",
                    description: Text(err)
                )
            } else {
                ShelfSection(title: "", items: store.suggested, selectedRef: $selectedRef)
            }
        }
        // nice-to-have for smooth updates
        .animation(.easeInOut, value: store.suggested)
        .animation(.easeInOut, value: store.isLoading)
    }
}

// MARK: - Suggestions Helper
private final class SuggestionsHolder: ObservableObject {
    @Published var store: SuggestionsStore?

    @MainActor
    func ensureStore(env: AppEnvironment, modelContext: ModelContext) {
        guard store == nil else { return }
        let newStore = SuggestionsStore(env: env, modelContext: modelContext)
        store = newStore
        // Kick off the first load NOW so the UI has data on first appearance
        Task { await newStore.refresh() }
    }
}

// Convenience accessor used in the body
private extension SearchView {
    var store: SuggestionsStore? { suggestionsHolder.store }
}

// MARK: - Preview Provider
#Preview {
    // In-memory SwiftData container for previews
    let schema = Schema([MediaItem.self, ProgressItem.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])

//    // Preview environment object
//    let env = AppEnvironment(modelContainer: container, contentAPI: MockAPI())
    
    // Load your actual TMDB key from Secrets.plist
    let env = AppEnvironment(
        modelContainer: container,
        contentAPI: TMDBClient(apiKey: Secrets.tmdbAPIKey)
    )

    return SearchView()
        .environmentObject(env)
        .modelContainer(container)
}



