import SwiftUI

struct ContinueWatchingEpisodeTile<ExtraMenu: View>: View {
    let showTitle: String
    var episodeName: String? = nil
    let episodeRef: EpisodeRef
    let stillPath: String?
    let fallbackPosterPath: String?
    let remainingEpisodes: Int
    var usesFrostedFooter = true
    @ViewBuilder var extraMenu: () -> ExtraMenu

    @Namespace private var navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let width: CGFloat = 176
    private let height: CGFloat = 99
    private var cornerRadius: CGFloat {
        usesFrostedFooter ? 18 : PosterImage.defaultCornerRadius
    }

    var body: some View {
        NavigationLink {
            EpisodeView(ref: episodeRef)
                .navigationTransition(.zoom(sourceID: transitionID, in: navigation))
        } label: {
            ZStack(alignment: .topLeading) {
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
                .id(episodeRef)
                .transition(.opacity)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: episodeRef)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(showTitle), Season \(episodeRef.season) Episode \(episodeRef.episode), Continue Watching")
        .contextMenu {
            if !usesFrostedFooter {
                Text(remainingEpisodes == 1 ? "1 Episode Remaining" : "\(remainingEpisodes) Episodes Remaining")
                Divider()
            }
            NavigationLink {
                EpisodeView(ref: episodeRef)
            } label: {
                Label("Go to Episode", systemImage: "info.circle")
            }
            extraMenu()
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if usesFrostedFooter {
            frostedArtwork
        } else {
            episodeStill
                .artworkGlassBorder(cornerRadius: cornerRadius)
                .overlay(alignment: .topLeading) {
                    Text("S\(episodeRef.season) E\(episodeRef.episode)")
                        .font(.caption2.bold())
                        .padding(3)
                        .glassEffect()
                        .padding(3)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
        }
    }

    private var episodeStill: some View {
        EpisodeStillImage(
            path: stillPath,
            fallbackPosterPath: fallbackPosterPath,
            width: width,
            height: height,
            cornerRadius: cornerRadius,
            blursFooter: usesFrostedFooter
        )
    }

    private var frostedArtwork: some View {
        ZStack(alignment: .bottomLeading) {
            episodeStill

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.65)
                .mask {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: UnitPoint(x: 0.5, y: 0.62),
                        endPoint: UnitPoint(x: 0.5, y: 0.94)
                    )
                }
                .allowsHitTesting(false)

            LinearGradient(
                colors: [.clear, .black.opacity(0.32)],
                startPoint: UnitPoint(x: 0.5, y: 0.64),
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            Text(episodeMetadata)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .allowsHitTesting(false)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.2)],
                        startPoint: UnitPoint(x: 0.5, y: 0.72),
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
                .allowsHitTesting(false)
        }
    }

    private var transitionID: MediaTileTransitionID {
        .episode(episodeRef)
    }

    private var episodeMetadata: String {
        let episode = "S\(episodeRef.season) E\(episodeRef.episode)"
        guard remainingEpisodes > 1 else { return episode }
        return "\(episode) • \(remainingEpisodes) Remaining"
    }
}

/// A sibling of the card's navigation link, so marking never opens the episode.
struct QuickEpisodeWatchButton: View {
    let showTitle: String
    let season: Int
    let episode: Int
    let isWorking: Bool
    var releasedProgress: (watched: Int, remaining: Int)? = nil
    let action: (@escaping () -> Void) async -> Void

    @State private var isSaving = false
    @State private var showsSpinner = false
    @State private var confirmationID: UUID?
    @State private var isSubmitting = false

    var body: some View {
        EpisodeWatchButton(
            isWatched: false,
            isWorking: isSaving && showsSpinner,
            progress: progressFraction,
            showsConfirmation: confirmationID != nil
        ) {
            guard !isSubmitting, !isWorking else { return }
            isSubmitting = true
            isSaving = true
            confirmationID = nil
            Task {
                await action {
                    isSaving = false
                    confirmationID = UUID()
                }
                isSaving = false
                isSubmitting = false
            }
        }
        .disabled(isSubmitting || isWorking)
        .opacity(isSaving && !showsSpinner ? 0.7 : 1)
        .accessibilityLabel("Mark \(showTitle), Season \(season) Episode \(episode) watched")
        .accessibilityHint("Updates this card to the next unwatched episode")
        .accessibilityValue(progressDescription)
        .task(id: isSaving) {
            showsSpinner = false
            guard isSaving else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            showsSpinner = true
        }
        .task(id: confirmationID) {
            guard confirmationID != nil else { return }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            confirmationID = nil
        }
    }

    private var progressFraction: Double? {
        guard let releasedProgress else { return nil }
        let total = releasedProgress.watched + releasedProgress.remaining
        guard total > 0 else { return nil }
        return Double(releasedProgress.watched) / Double(total)
    }

    private var progressDescription: Text {
        guard let releasedProgress else { return Text("") }
        let total = releasedProgress.watched + releasedProgress.remaining
        return Text("\(releasedProgress.watched) of \(total) released episodes watched, \(releasedProgress.remaining) remaining")
    }
}

/// Shared by episode rows and Continue Watching cards.
struct EpisodeWatchButton: View {
    let isWatched: Bool
    var isWorking = false
    var progress: Double? = nil
    var showsConfirmation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let ringWidth: CGFloat = 2.5
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isWorking && !showsConfirmation {
                    ProgressView().tint(.primary)
                } else if showsConfirmation {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffectsRemoved(reduceMotion)
                        .transition(
                            AsymmetricTransition(
                                insertion: .symbolEffect(.drawOn),
                                removal: .identity
                            )
                        )
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isWatched ? Color.white : Color.clear)
                }
            }
            .animation(reduceMotion ? nil : .default, value: showsConfirmation)
            .frame(width: 28, height: 28)
            .background(isWatched ? Color.accentColor : Color.clear, in: .circle)
            .glassEffect(.regular.interactive(), in: .circle)
            .overlay {
                if let progress {
                    Circle().strokeBorder(.white.opacity(0.35), lineWidth: ringWidth)
                    if progress > 0 {
                        Circle()
                            .inset(by: ringWidth / 2)
                            .trim(from: 0, to: progress)
                            .stroke(.white, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: progress)
                    }
                } else {
                    Circle().strokeBorder(isWatched ? Color.accentColor : Color.secondary, lineWidth: 2)
                }
            }
            .padding(.top, progress == nil ? 0 : 3)
            .padding(.trailing, progress == nil ? 0 : 3)
            .frame(width: 44, height: 44, alignment: progress == nil ? .center : .topTrailing)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }
}
