import SwiftUI

struct ContinueWatchingEpisodeTile<ExtraMenu: View>: View {
    let showTitle: String
    var episodeName: String? = nil
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
            VStack(alignment: .leading, spacing: 4) {
                artwork
                    .matchedTransitionSource(id: transitionID, in: navigation)
                Text(showTitle)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(episodeName ?? "")
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(episodeName?.isEmpty != false)
            }
            .frame(width: width, alignment: .leading)
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

/// A sibling of the card's navigation link, so marking never opens the episode.
struct QuickEpisodeWatchButton: View {
    let showTitle: String
    let season: Int
    let episode: Int
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        EpisodeWatchButton(isWatched: false, isWorking: isWorking, action: action)
        .disabled(isWorking)
        .accessibilityLabel("Mark \(showTitle), Season \(season) Episode \(episode) watched")
        .accessibilityHint("Updates this card to the next unwatched episode")
    }
}

/// Shared by episode rows and Continue Watching cards.
struct EpisodeWatchButton: View {
    let isWatched: Bool
    var isWorking = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isWorking {
                    ProgressView().tint(.primary)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isWatched ? Color.white : Color.clear)
                }
            }
            .frame(width: 28, height: 28)
            .background(isWatched ? Color.accentColor : Color.clear, in: .circle)
            .glassEffect(.regular.interactive(), in: .circle)
            .overlay {
                Circle().strokeBorder(isWatched ? Color.accentColor : Color.secondary, lineWidth: 2)
            }
            .frame(width: 44, height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }
}
