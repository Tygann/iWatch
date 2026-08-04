import Foundation
import SwiftData

@Model
final class ShowDispositionRecord {
    var mediaKey: String = ""
    var generationID: String = ""
    var tmdbID: Int = 0
    var traktID: Int?
    var dispositionRaw: String = ShowDisposition.active.rawValue
    var updatedAt: Date = Date.distantPast

    init(
        showID: MediaID,
        disposition: ShowDisposition,
        updatedAt: Date = .now,
        generationID: String = ""
    ) {
        mediaKey = showID.stableKey
        tmdbID = showID.tmdbID
        traktID = showID.traktID
        dispositionRaw = disposition.rawValue
        self.updatedAt = updatedAt
        self.generationID = generationID
    }

    var disposition: ShowDisposition {
        get { ShowDisposition(rawValue: dispositionRaw) ?? .active }
        set { dispositionRaw = newValue.rawValue }
    }
}
