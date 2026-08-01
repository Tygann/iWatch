import SwiftUI
import UIKit

struct CachedArtworkImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let targetSize: CGSize
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var loaded: (key: String, image: UIImage)?

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
            if let displayedImage {
                content(Image(uiImage: displayedImage))
            } else {
                placeholder()
            }
        }
        .task(id: loadID) {
            let requestedID = loadID
            if let image = ArtworkMemoryCache.shared.image(forKey: requestedID) {
                loaded = (requestedID, image)
                return
            }

            loaded = nil
            guard let url else { return }
            let image = await ArtworkLoader.shared.image(
                for: url,
                targetSize: targetSize,
                displayScale: displayScale
            )
            guard !Task.isCancelled, loadID == requestedID, let image else { return }
            loaded = (requestedID, image)
        }
    }

    private var displayedImage: UIImage? {
        if let loaded, loaded.key == loadID {
            return loaded.image
        }
        return ArtworkMemoryCache.shared.image(forKey: loadID)
    }

    private var loadID: String {
        guard let url else { return "missing" }
        let pixels = ArtworkLoader.pixelSize(for: targetSize, displayScale: displayScale)
        return ArtworkLoader.cacheKey(url: url, pixelSize: pixels)
    }
}
