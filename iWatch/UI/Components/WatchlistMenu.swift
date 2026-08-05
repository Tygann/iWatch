import SwiftUI

struct WatchlistMenu: View {
    let ref: MediaRef
    let title: String
    let posterPath: String?

    @Environment(AppContainer.self) private var container
    @Environment(AppSession.self) private var session
    @State private var isInWatchlist = false
    @State private var hasLoadedWatchlistState = false

    var body: some View {
        Group {
            if !hasLoadedWatchlistState {
                ProgressView()
            } else if isInWatchlist {
                Button(role: .destructive) {
                    Task {
                        try? await container.libraryRepository.setWatchlist(false, for: ref)
                        await MainActor.run {
                            isInWatchlist = false
                            session.markLibraryUpdated(syncIfConnected: true)
                        }
                    }
                } label: {
                    Label("Remove from Watchlist", systemImage: "minus.circle")
                }
            } else {
                Button {
                    Task {
                        try? await container.libraryRepository.setWatchlist(true, for: ref)
                        await MainActor.run {
                            isInWatchlist = true
                            session.markLibraryUpdated(syncIfConnected: true)
                        }
                    }
                } label: {
                    Label("Add to Watchlist", systemImage: "plus.circle")
                }
            }
        }
        .task(id: session.libraryRevision) {
            isInWatchlist = await container.libraryRepository.isInWatchlist(ref)
            hasLoadedWatchlistState = true
        }
    }
}
