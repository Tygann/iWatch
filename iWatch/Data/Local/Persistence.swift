import Foundation
import SwiftData

nonisolated final class Persistence: @unchecked Sendable {
    let modelContainer: ModelContainer

    init(inMemory: Bool = false,
         storeURL: URL? = nil,
         cloudKitDatabase: ModelConfiguration.CloudKitDatabase? = nil) {
        let schema = Schema([
            MediaRecord.self,
            EpisodeRecord.self,
            WatchlistRecord.self,
            WatchedEventRecord.self,
            ShowDispositionRecord.self,
            SyncOperationRecord.self,
            SyncStateRecord.self,
            LibraryGenerationRecord.self
        ])

        let cloudKit = cloudKitDatabase ?? (inMemory ? .none : .private("iCloud.com.tyler.iWatch"))
        let config: ModelConfiguration = {
            if let storeURL {
                return ModelConfiguration(
                    "iWatch",
                    schema: schema,
                    url: storeURL,
                    allowsSave: true,
                    cloudKitDatabase: inMemory ? .none : cloudKit
                )
            } else {
                return ModelConfiguration(
                    "iWatch",
                    schema: schema,
                    isStoredInMemoryOnly: inMemory,
                    allowsSave: true,
                    cloudKitDatabase: inMemory ? .none : cloudKit
                )
            }
        }()

        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    func makeContext() -> ModelContext {
        ModelContext(modelContainer)
    }
}
