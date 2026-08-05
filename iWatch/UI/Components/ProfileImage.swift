import SwiftUI

struct ProfileImage: View {
    let path: String?
    var width: CGFloat = 100
    var height: CGFloat = 140
    var cornerRadius: CGFloat = 12
    var cropAlignment: Alignment = .center
    var cropOffsetY: CGFloat = 0

    var body: some View {
        let url = ImageURLBuilder.make(path, size: .profile)

        CachedArtworkImage(url: url, targetSize: CGSize(width: width, height: height)) { image in
            image
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height, alignment: cropAlignment)
                .offset(y: cropOffsetY)
        } placeholder: {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.gray.opacity(0.12))
                Image(systemName: "person.crop.rectangle")
                    .font(.title3)
                    .foregroundStyle(.gray.opacity(0.5))
            }
        }
        .frame(width: width, height: height, alignment: cropAlignment)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .clipped()
        .accessibilityHidden(true)
    }
}
