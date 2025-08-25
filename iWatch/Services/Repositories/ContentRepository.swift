import Foundation
import SwiftData

@MainActor
final class ContentRepository {
    private let api: ContentAPI
    private let context: ModelContext

    init(api: ContentAPI, context: ModelContext) {
        self.api = api
        self.context = context
    }

    func addToWatchlist(simple: SimpleDTO, kind: MediaItem.Kind) {
        let uniqueID = "\(kind.rawValue):\(simple.id)"
        let existing = try? context.fetch(FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { $0.id == uniqueID }
        )).first

        if let media = existing {
            toggleWatchlist(for: media, true)
            return
        }

        // pull overview (and normalize year if you want)
//        let (overview, fixedYear) = await fetchOverviewAndYear(for: simple)
        
        let media = MediaItem(
            remoteID: simple.id,
            kind: kind,
            title: simple.title,
            posterPath: simple.posterPath,
            overview: nil,
//            overview: overview,
            year: simple.year
        )
        context.insert(media)

        let progress = ProgressItem(media: media)
        progress.isInWatchlist = true
        context.insert(progress)

        try? context.save()
    }

    func toggleWatchlist(for media: MediaItem, _ enabled: Bool) {
        let mediaID = media.id
        let progress = try? context.fetch(FetchDescriptor<ProgressItem>(
            predicate: #Predicate<ProgressItem> { $0.media.id == mediaID }
        )).first

        if let p = progress {
            p.isInWatchlist = enabled
        } else {
            let p = ProgressItem(media: media)
            p.isInWatchlist = enabled
            context.insert(p)
        }
        try? context.save()
    }

    func watchlist() -> [MediaItem] {
        let items = try? context.fetch(FetchDescriptor<ProgressItem>(
            predicate: #Predicate<ProgressItem> { $0.isInWatchlist },
            sortBy: [SortDescriptor(\.media.dateAdded, order: .reverse)]
        ))
        return items?.map(\.media) ?? []
    }
}
