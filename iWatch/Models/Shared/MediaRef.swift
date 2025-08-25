import Foundation

// MARK: - MediaRef: Tiny identifier used for navigation and API calls (id + kind). No persistence concerns.
public struct MediaRef: Hashable, Sendable, Identifiable {
    public enum Kind { case movie, tv }
    public let id: Int
    public let kind: Kind

    public init(id: Int, kind: Kind) {
        self.id = id
        self.kind = kind
    }
}



//struct MediaRef: Hashable {
//    let id: Int
//    let kind: MediaItem.Kind   // .movie or .tv
//}
