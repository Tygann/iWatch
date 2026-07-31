import Foundation
import SwiftData

@Model
final class LibraryGenerationRecord {
    var key: String = "library"
    var generationID: String = LibraryGenerationPolicy.legacyGenerationID
    var changedAt: Date = Date.distantPast

    init(generationID: String, changedAt: Date) {
        self.key = "library"
        self.generationID = generationID
        self.changedAt = changedAt
    }
}

nonisolated enum LibraryGenerationPolicy {
    static let legacyGenerationID = "legacy-v1"

    static func currentGeneration(in context: ModelContext) -> String {
        let markers = (try? context.fetch(FetchDescriptor<LibraryGenerationRecord>())) ?? []
        guard let current = markers.max(by: { $0.changedAt < $1.changedAt }) else {
            let marker = LibraryGenerationRecord(generationID: legacyGenerationID, changedAt: .distantPast)
            context.insert(marker)
            return legacyGenerationID
        }

        for duplicate in markers where duplicate !== current {
            context.delete(duplicate)
        }
        return current.generationID
    }

    @discardableResult
    static func rotateGeneration(in context: ModelContext, at date: Date = .now) -> String {
        let markers = (try? context.fetch(FetchDescriptor<LibraryGenerationRecord>())) ?? []
        let marker = markers.max(by: { $0.changedAt < $1.changedAt })
            ?? LibraryGenerationRecord(generationID: legacyGenerationID, changedAt: .distantPast)
        if marker.modelContext == nil {
            context.insert(marker)
        }
        for duplicate in markers where duplicate !== marker {
            context.delete(duplicate)
        }

        marker.generationID = UUID().uuidString
        marker.changedAt = date
        return marker.generationID
    }

    static func belongsToCurrentGeneration(_ generationID: String, current: String) -> Bool {
        generationID == current || (current == legacyGenerationID && generationID.isEmpty)
    }
}
