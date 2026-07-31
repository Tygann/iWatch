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
            SyncOperationRecord.self,
            SyncStateRecord.self
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
            #if DEBUG
            if inMemory == false, storeURL == nil {
                Self.removeSwiftDataStores()
                self.modelContainer = try! ModelContainer(for: schema, configurations: [config])
            } else {
                fatalError("Failed to create ModelContainer: \(error)")
            }
            #else
            fatalError("Failed to create ModelContainer: \(error)")
            #endif
        }
    }

    func makeContext() -> ModelContext {
        ModelContext(modelContainer)
    }
}

private extension Persistence {
    /// Deletes likely SwiftData store files in Application Support.
    nonisolated static func removeSwiftDataStores() {
        let fm = FileManager.default
        let base = URL.applicationSupportDirectory
        guard let contents = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { return }

        for url in contents {
            // SwiftData uses `.store` files (and may create -wal/-shm sidecars)
            if url.pathExtension == "store"
                || url.lastPathComponent.hasSuffix("-wal")
                || url.lastPathComponent.hasSuffix("-shm") {
                try? fm.removeItem(at: url)
            }
        }
    }
}
