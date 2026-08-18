import SwiftUI

struct ContinueWatchingEpisodeTile<ExtraMenu: View>: View {
    let showTitle: String
    let episodeRef: EpisodeRef
    let stillPath: String?
    let fallbackPosterPath: String?
    let remainingEpisodes: Int
    @ViewBuilder var extraMenu: () -> ExtraMenu

    @Namespace private var navigation

    private let width: CGFloat = 176
    private let height: CGFloat = 99
    private let cornerRadius: CGFloat = 18

    var body: some View {
        NavigationLink {
            EpisodeView(ref: episodeRef)
                .navigationTransition(.zoom(sourceID: transitionID, in: navigation))
        } label: {
            artwork
                .matchedTransitionSource(id: transitionID, in: navigation)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(showTitle), Season \(episodeRef.season) Episode \(episodeRef.episode), Continue Watching")
        .contextMenu {
            NavigationLink {
                EpisodeView(ref: episodeRef)
            } label: {
                Label("Go to Episode", systemImage: "info.circle")
            }
            extraMenu()
        }
    }

    private var artwork: some View {
        ZStack(alignment: .bottomLeading) {
            EpisodeStillImage(
                path: stillPath,
                fallbackPosterPath: fallbackPosterPath,
                width: width,
                height: height,
                cornerRadius: cornerRadius
            )

            Rectangle()
                .fill(.thinMaterial)
                .mask(bottomFadeMask)

            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 0))
                .mask(bottomFadeMask)
                .allowsHitTesting(false)

            Text(episodeMetadata)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(7)
                .allowsHitTesting(false)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    private var transitionID: MediaTileTransitionID {
        .episode(episodeRef)
    }

    private var episodeMetadata: String {
        let episode = "S\(episodeRef.season) E\(episodeRef.episode)"
        guard remainingEpisodes > 1 else { return episode }
        return "\(episode) • \(remainingEpisodes) Remaining"
    }

    private var bottomFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.58),
                .init(color: .black.opacity(0.75), location: 0.8),
                .init(color: .black, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
