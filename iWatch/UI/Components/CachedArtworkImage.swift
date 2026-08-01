import SwiftUI
import UIKit

struct CachedArtworkImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let targetSize: CGSize
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var loadedImage: UIImage?

    init(
        url: URL?,
        targetSize: CGSize,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.targetSize = targetSize
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let loadedImage {
                content(Image(uiImage: loadedImage))
            } else {
                placeholder()
            }
        }
        .task(id: loadID) {
            loadedImage = nil
            guard let url else { return }
            let image = await ArtworkLoader.shared.image(
                for: url,
                targetSize: targetSize,
                displayScale: displayScale
            )
            guard !Task.isCancelled else { return }
            loadedImage = image
        }
    }

    private var loadID: String {
        guard let url else { return "missing" }
        let pixels = ArtworkLoader.pixelSize(for: targetSize, displayScale: displayScale)
        return ArtworkLoader.cacheKey(url: url, pixelSize: pixels)
    }
}
