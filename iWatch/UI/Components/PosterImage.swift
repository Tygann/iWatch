// PosterImage.swift
import SwiftUI

struct PosterImage: View {
    static let aspectRatio: CGFloat = 2.0 / 3.0

    let path: String?
    var width: CGFloat = 110
    var cornerRadius: CGFloat = 12

    private var height: CGFloat {
        width / Self.aspectRatio
    }

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
        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
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
