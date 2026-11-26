import ImageIO
import UIKit

// Decode at a bounded resolution and normalize EXIF orientation before cropping.
// The original photo is never uploaded; only the selected square is exported.
enum AvatarImageService {
    enum PhotoError: LocalizedError {
        case unreadable
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .unreadable: "That photo couldn’t be read. Choose another image."
            case .encodingFailed: "That photo couldn’t be prepared. Choose another image."
            }
        }
    }
    static func image(from data: Data) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
              ] as CFDictionary) else {
            throw PhotoError.unreadable
        }
        return UIImage(cgImage: image)
    }

    static func crop(_ image: UIImage, zoom: CGFloat, horizontal: CGFloat, vertical: CGFloat) throws -> Data {
        let side: CGFloat = 512
        let scale = max(side / image.size.width, side / image.size.height) * zoom
        let width = image.size.width * scale
        let height = image.size.height * scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let cropped = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(
                x: (side - width) / 2 + horizontal * (width - side) / 2,
                y: (side - height) / 2 + vertical * (height - side) / 2,
                width: width, height: height
            ))
        }
        guard let png = cropped.pngData() else {
            throw PhotoError.encodingFailed
        }
        return png
    }
}
