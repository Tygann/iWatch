import Foundation
import ImageIO
import UIKit

// MARK: - Artwork Cache

nonisolated final class ArtworkMemoryCache: @unchecked Sendable {
    static let shared = ArtworkMemoryCache()

    private final class Entry: NSObject {
        let image: UIImage
        let cachedAt = Date()
        init(image: UIImage) { self.image = image }
    }
    private let images = NSCache<NSString, Entry>()

    init(memoryCapacity: Int = 48 * 1_024 * 1_024, countLimit: Int = 250) {
        images.totalCostLimit = memoryCapacity
        images.countLimit = countLimit
    }

    func image(forKey key: String) -> UIImage? {
        guard let entry = images.object(forKey: key as NSString) else { return nil }
        let age = Date().timeIntervalSince(entry.cachedAt)
        guard age >= 0, age < 30 * 86400 else {
            images.removeObject(forKey: key as NSString)
            return nil
        }
        return entry.image
    }

    func insert(_ image: UIImage, forKey key: String) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        images.setObject(Entry(image: image), forKey: key as NSString, cost: cost)
    }

    func clear() {
        images.removeAllObjects()
    }
}

// MARK: - Artwork Loader

actor ArtworkLoader {
    static let shared = ArtworkLoader()

    private let decodedImages: ArtworkMemoryCache
    private let urlCache: URLCache
    private let session: URLSession
    private var cacheEpoch: Date?
    private let retentionDefaults: UserDefaults?
    private let currentDate: @Sendable () -> Date
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init(
        diskCapacity: Int = 256 * 1_024 * 1_024,
        directory: URL? = nil,
        protocolClasses: [AnyClass]? = nil,
        decodedImages: ArtworkMemoryCache = .shared,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        let urlCache = URLCache(
            memoryCapacity: 16 * 1_024 * 1_024,
            diskCapacity: diskCapacity,
            directory: directory
        )
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = urlCache
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.timeoutIntervalForRequest = 30
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }

        self.currentDate = currentDate
        self.retentionDefaults = directory == nil && protocolClasses == nil ? .standard : nil
        self.cacheEpoch = retentionDefaults?.object(forKey: "iWatch.artworkCacheEpoch.v1") as? Date
        self.urlCache = urlCache
        self.session = URLSession(configuration: configuration)
        self.decodedImages = decodedImages
    }

    func image(for url: URL, targetSize: CGSize, displayScale: CGFloat) async -> UIImage? {
        guard !Task.isCancelled else { return nil }

        // Bound disk and decoded cache age independently of CDN freshness headers.
        let now = currentDate()
        if cacheEpoch.map({ now.timeIntervalSince($0) >= 30 * 86400 || $0 > now }) ?? true {
            await clear()
            cacheEpoch = now
            retentionDefaults?.set(now, forKey: "iWatch.artworkCacheEpoch.v1")
        }
        let pixelSize = Self.pixelSize(for: targetSize, displayScale: displayScale)
        let key = Self.cacheKey(url: url, pixelSize: pixelSize)

        if let image = decodedImages.image(forKey: key) {
            return image
        }

        let task: Task<UIImage?, Never>
        if let existing = inFlight[key] {
            task = existing
        } else {
            let session = session
            task = Task {
                do {
                    var request = URLRequest(url: url)
                    request.cachePolicy = .useProtocolCachePolicy
                    let (data, response) = try await session.data(for: request)
                    guard let response = response as? HTTPURLResponse,
                          (200..<300).contains(response.statusCode),
                          response.mimeType?.hasPrefix("image/") != false else {
                        return nil
                    }

                    return await Task.detached(priority: .utility) {
                        Self.downsample(data: data, pixelSize: pixelSize, displayScale: displayScale)
                    }.value
                } catch {
                    return nil
                }
            }
            inFlight[key] = task
        }

        let image = await task.value
        inFlight[key] = nil
        guard !Task.isCancelled, let image else { return nil }

        decodedImages.insert(image, forKey: key)
        return image
    }

    func clear() async {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        decodedImages.clear()
        urlCache.removeAllCachedResponses()
    }

    nonisolated static func cacheKey(url: URL, pixelSize: CGSize) -> String {
        "\(url.absoluteString)|\(Int(pixelSize.width.rounded(.up)))x\(Int(pixelSize.height.rounded(.up)))"
    }

    nonisolated static func pixelSize(for targetSize: CGSize, displayScale: CGFloat) -> CGSize {
        CGSize(
            width: max(1, targetSize.width * displayScale),
            height: max(1, targetSize.height * displayScale)
        )
    }

    nonisolated private static func downsample(
        data: Data,
        pixelSize: CGSize,
        displayScale: CGFloat
    ) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let maximumPixelSize = max(pixelSize.width, pixelSize.height)
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: image, scale: displayScale, orientation: .up)
    }
}

// MARK: - Image Service

struct ImageService {
    let artworkLoader: ArtworkLoader

    init(artworkLoader: ArtworkLoader = .shared) {
        self.artworkLoader = artworkLoader
    }
}

func clearImageCache() async {
    await ArtworkLoader.shared.clear()
}
