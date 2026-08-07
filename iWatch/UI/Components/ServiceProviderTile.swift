import SwiftUI

struct ServiceProviderTile: View {
    let name: String
    let logoPath: String?
    let size: CGFloat
    let caption: String?
    var captionLineLimit = 2
    var captionWeight: Font.Weight = .semibold

    private var cornerRadius: CGFloat {
        max(10, size * 0.22)
    }

    var body: some View {
        VStack(spacing: 6) {
            CachedArtworkImage(
                url: ImageURLBuilder.make(logoPath, size: .profile),
                targetSize: CGSize(width: size, height: size)
            ) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.gray.opacity(0.12))
                    .overlay {
                        Image(systemName: "play.tv")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))

            if let caption {
                Text(caption)
                    .font(.caption.weight(captionWeight))
                    .lineLimit(captionLineLimit, reservesSpace: captionLineLimit > 1)
                    .multilineTextAlignment(.center)
                    .frame(width: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let caption, caption != name else { return name }
        return "\(name), \(caption)"
    }
}
