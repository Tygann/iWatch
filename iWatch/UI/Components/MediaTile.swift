import SwiftUI

enum MediaTileTransitionID: Hashable {
    case media(MediaRef)
    case episode(EpisodeRef)
}

struct MediaTile<Destination: View, ExtraMenu: View>: View {
    let ref: MediaRef
    let title: String
    let posterPath: String?
    var showTitle: Bool = false
    var showsWatchlistAction = true
    let transitionID: MediaTileTransitionID

    @ViewBuilder var destination: () -> Destination
    @ViewBuilder var extraMenu: () -> ExtraMenu

    @Namespace private var navigation

    init(
        ref: MediaRef,
        title: String,
        posterPath: String?,
        showTitle: Bool = false,
        showsWatchlistAction: Bool = true,
        transitionID: MediaTileTransitionID,
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder extraMenu: @escaping () -> ExtraMenu
    ) {
        self.ref = ref
        self.title = title
        self.posterPath = posterPath
        self.showTitle = showTitle
        self.showsWatchlistAction = showsWatchlistAction
        self.transitionID = transitionID
        self.destination = destination
        self.extraMenu = extraMenu
    }

    var body: some View {
        NavigationLink {
            destination()
                .navigationTransition(.zoom(sourceID: transitionID, in: navigation))
        } label: {
            VStack(spacing: 6) {
                PosterImage(path: posterPath)
                if showTitle {
                    Text(title)
                        .font(.caption)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .matchedTransitionSource(id: transitionID, in: navigation)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .contextMenu {
            NavigationLink {
                destination()
            } label: {
                Label(contextMenuDestinationTitle, systemImage: "info.circle")
            }
            extraMenu()
            if showsWatchlistAction {
                WatchlistMenu(ref: ref, title: title, posterPath: posterPath)
            }
        }
    }

    private var contextMenuDestinationTitle: String {
        switch transitionID {
        case .episode:
            return "Go to Episode"
        case .media:
            return ref.kind == .show ? "Go to Show" : "Go to Movie"
        }
    }
}

extension MediaTile where Destination == MediaDetailView {
    init(
        ref: MediaRef,
        title: String,
        posterPath: String?,
        showTitle: Bool = false,
        showsWatchlistAction: Bool = true,
        @ViewBuilder extraMenu: @escaping () -> ExtraMenu
    ) {
        self.init(
            ref: ref,
            title: title,
            posterPath: posterPath,
            showTitle: showTitle,
            showsWatchlistAction: showsWatchlistAction,
            transitionID: .media(ref),
            destination: { MediaDetailView(ref: ref) },
            extraMenu: extraMenu
        )
    }
}

extension MediaTile where Destination == MediaDetailView, ExtraMenu == EmptyView {
    init(
        ref: MediaRef,
        title: String,
        posterPath: String?,
        showTitle: Bool = false,
        showsWatchlistAction: Bool = true
    ) {
        self.init(
            ref: ref,
            title: title,
            posterPath: posterPath,
            showTitle: showTitle,
            showsWatchlistAction: showsWatchlistAction,
            extraMenu: { EmptyView() }
        )
    }
}
