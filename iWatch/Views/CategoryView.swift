import SwiftUI

struct BrowseCategoryView: View {
    let kind: MediaItem.Kind
    @EnvironmentObject private var env: AppEnvironment

    @State private var trending: [SimpleDTO] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var detailRef: MediaRef? = nil   // <- sheet selection

    private var title: String { kind == .movie ? "Movies" : "Shows" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Trending
                ShelfSection(title: "Trending", items: trending, selectedRef: $detailRef)

                // TODO: Add other sections (Popular, Top Rated, etc.) when you expose them on ContentAPI
            }
            .padding(.horizontal)
            .padding(.top, 12)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadTrending() }
        .overlay {
            if isLoading {
                ProgressView().scaleEffect(1.2)
            } else if let errorText {
                ContentUnavailableView("Error",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(errorText))
            }
        }
        // Single sheet presenter for this screen
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

    @MainActor
    private func loadTrending() async {
        isLoading = true
        defer { isLoading = false }

        do {
            switch kind {
            case .movie:
                trending = try await env.contentAPI.trendingMovies(page: 1)
            case .tv:
                trending = try await env.contentAPI.trendingTV(page: 1)
            }
        } catch {
            errorText = "Couldn't load \(title.lowercased())."
        }
    }
}

// MARK: - Shelf (horizontal scroller)
//private struct ShelfSection: View {
//    let title: String
//    let items: [SimpleDTO]
//    @Binding var selectedRef: MediaRef?
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 12) {
//            Text(title)
//                .font(.title2.bold())
//                .padding(.horizontal, 4)
//
//            ScrollView(.horizontal, showsIndicators: false) {
//                LazyHStack(spacing: 12) {
//                    ForEach(items, id: \.id) { item in
//                        MediaTile(
//                            ref: .init(id: item.id, kind: item.kind),
//                            title: item.title,
//                            posterPath: item.posterPath,
//                            showTitle: true,                 // subtitle under poster (like your prior UI)
//                            selectedRef: $selectedRef        // <-- tap opens the sheet
//                        )
//                        // If you want the exact old size, you can wrap the tile in a fixed frame:
//                        .frame(width: 120)                  // keeps 2-line title width consistent
//                    }
//                }
//                .padding(.horizontal, 4)
//            }
//        }
//    }
//}

//// MARK: - Preview Provider
//#Preview {
//    // In-memory SwiftData container for previews
//    let schema = Schema([MediaItem.self, ProgressItem.self])
//    let config = ModelConfiguration(isStoredInMemoryOnly: true)
//    let container = try! ModelContainer(for: schema, configurations: [config])
//    
//    // Load your actual TMDB key from Secrets.plist
//    let env = AppEnvironment(
//        modelContainer: container,
//        contentAPI: TMDBClient(apiKey: Secrets.tmdbAPIKey)
//    )
//
//    return BrowseCategoryView(kind: .tv)
//        .environmentObject(env)
//        .modelContainer(container)
//}
