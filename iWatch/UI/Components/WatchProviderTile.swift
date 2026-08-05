import SwiftUI

struct WatchProviderTile: View {
    let provider: MediaSupplementaryDetails.WatchProvider
    let availabilityLabel: String

    var body: some View {
        VStack(spacing: 6) {
            CachedArtworkImage(
                url: ImageURLBuilder.make(provider.logoPath, size: .profile),
                targetSize: CGSize(width: 54, height: 54)
            ) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.gray.opacity(0.12))
                    .overlay {
                        Image(systemName: "play.tv")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .glassEffect(.regular, in: .rect(cornerRadius: 12))

            Text(availabilityLabel)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .multilineTextAlignment(.center)
        }
        .frame(width: 54)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider.name), \(availabilityLabel)")
    }
}
