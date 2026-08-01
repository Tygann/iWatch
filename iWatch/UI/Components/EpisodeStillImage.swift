import SwiftUI

struct EpisodeStillImage: View {
    let path: String?
    var width: CGFloat = 120
    var height: CGFloat = 68
    var cornerRadius: CGFloat = 12

    var body: some View {
        let url = ImageURLBuilder.make(path, size: .episodeStill)

        CachedArtworkImage(url: url, targetSize: CGSize(width: width, height: height)) { image in
            image
                .resizable()
                .scaledToFill()
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
