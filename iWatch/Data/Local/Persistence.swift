import Foundation
import SwiftData

nonisolated final class Persistence: @unchecked Sendable {
    let modelContainer: ModelContainer

    init(inMemory: Bool = false,
         storeURL: URL? = nil,
         cloudKitDatabase: ModelConfiguration.CloudKitDatabase? = nil) throws {
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

        // Opening errors propagate to startup. Never replace, remove, or reroute this store.
        self.modelContainer = try ModelContainer(for: schema, configurations: [config])
    }

    // Only provider metadata is disposable. Library/history/outbox rows are never touched.
    // Unknown legacy provenance expires immediately; 150 days leaves margin below six months.
    func makeMetadataContext(now: Date = .now) throws -> ModelContext {
        let context = makeContext()
        let cutoff = now.addingTimeInterval(-150 * 86400)
        let media = try context.fetch(FetchDescriptor<MediaRecord>(
            predicate: #Predicate { $0.metadataCachedAt <= cutoff || $0.metadataCachedAt > now }
        ))
        let episodes = try context.fetch(FetchDescriptor<EpisodeRecord>(
            predicate: #Predicate { $0.metadataCachedAt <= cutoff || $0.metadataCachedAt > now }
        ))
        for record in media { context.delete(record) }
        for record in episodes { context.delete(record) }
        if context.hasChanges { try context.save() }
        return context
    }

    func makeContext() -> ModelContext {
        ModelContext(modelContainer)
    }
}
