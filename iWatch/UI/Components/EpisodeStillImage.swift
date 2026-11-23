import SwiftUI

struct EpisodeStillImage: View {
    let path: String?
    var fallbackPosterPath: String? = nil
    var width: CGFloat = 120
    var height: CGFloat = 68
    var cornerRadius: CGFloat = 12
    var blursFooter = false

    var body: some View {
        let url = ImageURLBuilder.make(path, size: .episodeStill)
            ?? ImageURLBuilder.make(fallbackPosterPath, size: .posterTile)

        CachedArtworkImage(url: url, targetSize: CGSize(width: width, height: height)) { image in
            let still = image.resizable().scaledToFill()
                .frame(width: width, height: height)

            still.overlay {
                if blursFooter {
                    still
                        .blur(radius: 12, opaque: true)
                        .mask {
                            LinearGradient(
                                colors: [.clear, .black],
                                startPoint: UnitPoint(x: 0.5, y: 0.64),
                                endPoint: .bottom
                            )
                        }
                        .allowsHitTesting(false)
                }
            }
        } placeholder: {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.gray.opacity(0.12))
                Image(systemName: "photo")
                    .font(.callout)
                    .foregroundStyle(.gray.opacity(0.5))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .clipped()
        .accessibilityHidden(true)
    }
}
