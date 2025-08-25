import Foundation
import SwiftData

@Model
final class ProgressItem {
    @Relationship var media: MediaItem
    var lastWatchedAt: Date?
    var isInWatchlist: Bool = false

    // TV specifics
    var season: Int?
    var episode: Int?

    // Movie specifics
    var watched: Bool = false

    // NEW: treat this as “this show has episodes left for me to watch”
    var hasUnwatched: Bool = true

    init(media: MediaItem) { self.media = media }
}
