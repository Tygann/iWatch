import SwiftUI
import SwiftData

struct WatchlistMenu: View {
    let ref: MediaRef
    let title: String
    let posterPath: String?

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        if isInWatchlist {
            Button(role: .destructive) {
                removeFromWatchlist()
            } label: {
                Label("Remove from Watchlist", systemImage: "minus.circle")
            }
        } else {
            Button {
                Task { await addToWatchlist() }
            } label: {
                Label("Add to Watchlist", systemImage: "plus.circle")
            }
        }
    }

    // MARK: - Watchlist helpers
    private var isInWatchlist: Bool {
        progressForUniqueID(uniqueID) != nil
    }

    private func addToWatchlist() async {
        let repo = ContentRepository(api: env.contentAPI, context: context)
        let simple = SimpleDTO(id: ref.id, kind: ref.kind, title: title, posterPath: posterPath, year: nil)
//        await repo.addToWatchlist(simple: simple, kind: mediaItemKind(from: ref.kind))
        repo.addToWatchlist(simple: simple, kind: mediaItemKind(from: ref.kind))
    }

    private func removeFromWatchlist() {
        // Find the MediaItem then toggle
        if let media = try? context.fetch(
            FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == uniqueID })
        ).first {
            let repo = ContentRepository(api: env.contentAPI, context: context)
            repo.toggleWatchlist(for: media, false)
        }
    }

    private var uniqueID: String {
        "\(mediaItemKind(from: ref.kind).rawValue):\(ref.id)"
    }

    private func progressForUniqueID(_ id: String) -> ProgressItem? {
        try? context.fetch(
            FetchDescriptor<ProgressItem>(
                predicate: #Predicate { $0.media.id == id && $0.isInWatchlist == true }
            )
        ).first
    }

    private func mediaItemKind(from kind: MediaRef.Kind) -> MediaItem.Kind {
        switch kind {
        case .movie: return .movie
        case .tv:    return .tv
        }
    }
}
