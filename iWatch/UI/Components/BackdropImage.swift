// BackdropImage.swift
import SwiftUI

struct BackdropImage: View {
    let path: String?
    var height: CGFloat = 220

    var body: some View {
        let url = ImageURLBuilder.make(path, size: .backdrop)

        CachedArtworkImage(
            url: url,
            targetSize: CGSize(width: 780.0 / 3.0, height: height)
        ) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Rectangle().fill(.gray.opacity(0.12))
        }
        .frame(height: height)
        .clipped()
        .accessibilityHidden(true)
    }
}
