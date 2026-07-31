// ImageService.swift
import Foundation
import SDWebImage

/// Central place to tune SDWebImage caches & loaders. Views can just use SDWebImageSwiftUI or SDWebImage directly.
struct ImageService {
    init() {}

    // Your existing cache tuning
    static func configureDefaultCache() {
        let cache = SDImageCache.shared
        cache.config.maxDiskSize = 500 * 1024 * 1024
        cache.config.maxMemoryCost = 100 * 1024 * 1024
        cache.config.diskCacheExpireType = .accessDate
        cache.config.shouldUseWeakMemoryCache = true

        let loader = SDWebImageDownloader.shared
        loader.config.downloadTimeout = 30
        loader.config.executionOrder = .lifoExecutionOrder
    }

    // MARK: - URL builders (use your ImageURLBuilder)
    func posterURL(path: String?, width: Int = 342) -> URL? {
        ImageURLBuilder.make(path, size: .posterLarge) // or map width->size if you prefer
    }

    func backdropURL(path: String?, width: Int = 780) -> URL? {
        ImageURLBuilder.make(path, size: .backdrop)
    }

    enum Kind { case poster, backdrop }

    // MARK: - Prefetch convenience
    func prefetch(paths: [String], kind: Kind, width: Int = 342) {
        let urls: [URL] = paths.compactMap { p in
            switch kind {
            case .poster:   return posterURL(path: p, width: width)
            case .backdrop: return backdropURL(path: p, width: width)
            }
        }
        SDWebImagePrefetcher.shared.prefetchURLs(urls)
    }
}

// MARK: - Clear Image Cache Function
func clearImageCache() async {
    let cache = SDImageCache.shared
    cache.clearMemory()

    await withCheckedContinuation { continuation in
        cache.clearDisk {
            continuation.resume()
        }
    }
}
