// BackdropImage.swift
import SwiftUI
import SDWebImageSwiftUI

struct BackdropImage: View {
    let path: String?
    var height: CGFloat = 220

    var body: some View {
        let url = ImageURLBuilder.make(path, size: .backdrop)

        WebImage(url: url) { image in
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
