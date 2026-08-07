import SwiftUI

struct DiscoveryPosterTile: View {
    let item: SearchItem
    let showTitle: Bool
    let showKindBadge: Bool
    var subtitle: String? = nil
    var showYearBadge = true

    var body: some View {
        VStack(spacing: 6) {
            MediaTile(
                ref: item.mediaID,
                title: item.title,
                posterPath: item.posterPath,
                showTitle: showTitle
            )

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityLabel(accessibilityLabel)
        .overlay(alignment: .topLeading) {
            if showKindBadge {
                Image(systemName: item.kind == .movie ? "film.fill" : "tv.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(item.kind == .movie ? .purple : .blue)
                    .frame(width: 12, height: 12)
                    .padding(3)
                    .glassEffect(.regular, in: .circle)
                    .padding(3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showYearBadge, let year = item.year {
                Text(year)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(3)
                    .glassEffect()
                    .padding(3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 110)
    }

    private var accessibilityLabel: String {
        [item.title, item.kind == .movie ? "Movie" : "Show", item.year, subtitle]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
