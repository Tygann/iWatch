import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        TabView {
//            Tab("Search", systemImage: "magnifyingglass") {
//                SearchView()
//            }
            
            Tab("Movies", systemImage: "film") {
                MoviesView()
            }
            
            Tab("Shows", systemImage: "tv") {
                ShowsView()
            }
            
            Tab(role: .search) {
                SearchView()
            }
        }
    }
}

//#Preview {
//    ContentView()
//}

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

    return ContentView()
        .environmentObject(env)
        .modelContainer(container)
}
