import Foundation

nonisolated struct MediaID: Identifiable, Hashable, Codable, Sendable {
    let kind: MediaKind
    let id: Int
    var traktID: Int?

    init(kind: MediaKind, id: Int, traktID: Int? = nil) {
        self.kind = kind
        self.id = id
        self.traktID = traktID
    }

    var tmdbID: Int { id }
    var stableKey: String { "\(kind.rawValue):\(id)" }

    func merging(traktID: Int?) -> MediaID {
        MediaID(kind: kind, id: id, traktID: traktID ?? self.traktID)
    }
}

typealias MediaRef = MediaID
