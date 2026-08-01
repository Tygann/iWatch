// PosterImage.swift
import SwiftUI

struct PosterImage: View {
    let path: String?
    var width: CGFloat = 110
    var height: CGFloat = 165
    var cornerRadius: CGFloat = 12

    var body: some View {
        let url = ImageURLBuilder.make(path, size: width <= 120 ? .posterTile : .posterLarge)

        CachedArtworkImage(url: url, targetSize: CGSize(width: width, height: height)) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            placeholder
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .clipped()
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.gray.opacity(0.12))
            Image(systemName: "film")
                .font(.title3)
                .foregroundStyle(.gray.opacity(0.5))
        }
    }
}
