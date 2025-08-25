import Foundation
import SwiftData
import Combine

@MainActor
final class AppEnvironment: ObservableObject {
    let modelContainer: ModelContainer
    let contentAPI: ContentAPI
    let repository: ContentRepository

    init(modelContainer: ModelContainer, contentAPI: ContentAPI) {
        self.modelContainer = modelContainer
        self.contentAPI = contentAPI
        self.repository = ContentRepository(api: contentAPI, context: modelContainer.mainContext)
    }

    @MainActor
    static func makeDefault() -> AppEnvironment {
        let schema = Schema([MediaItem.self, ProgressItem.self])
        let config = ModelConfiguration(cloudKitDatabase: .automatic)
        let container = try! ModelContainer(for: schema, configurations: [config])

        let api = TMDBClient(apiKey: Secrets.tmdbAPIKey)
        return AppEnvironment(modelContainer: container, contentAPI: api)
    }
}

extension AppEnvironment {
    /// Pure mock: no networking. Great for instant previews.
    static var preview: AppEnvironment {
        let container = try! ModelContainer(
            for: ProgressItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return AppEnvironment(modelContainer: container, contentAPI: MockData())
    }
    
    /// Smart preview: uses TMDB if Secrets has a key, otherwise falls back to MockData.
    static var previewSmart: AppEnvironment {
        let container = try! ModelContainer(
            for: ProgressItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        
        let api: ContentAPI
        if !Secrets.tmdbAPIKey.isEmpty {
            api = TMDBClient(apiKey: Secrets.tmdbAPIKey)
        } else {
            api = MockData()
        }
        
        return AppEnvironment(modelContainer: container, contentAPI: api)
    }
}

//extension AppEnvironment {
//    static var preview: AppEnvironment {
//        // make an in-memory container just for previews
//        let container = try! ModelContainer(for: ProgressItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
//        return AppEnvironment(modelContainer: container, contentAPI: MockData())
//    }
//}

// MARK: - Secrets loader
enum Secrets {
    static let tmdbAPIKey: String = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let key = dict["TMDB_API_KEY"] as? String,
              !key.isEmpty
        else { fatalError("Missing TMDB_API_KEY in Secrets.plist") }
        return key
    }()
}


//enum Secrets {
//    static var tmdbAPIKey: String {
//        // Look for Secrets.plist bundled with the app.
//        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist")
//        else { fatalError("Missing Secrets.plist. Add it to the app target. See Secrets.example.plist.") }
//
//        // Read TMDB_API_KEY string
//        guard
//            let data = try? Data(contentsOf: url),
//            let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
//            let key = dict["TMDB_API_KEY"] as? String,
//            key.isEmpty == false
//        else { fatalError("TMDB_API_KEY missing or empty in Secrets.plist") }
//
//        return key
//    }
//}
