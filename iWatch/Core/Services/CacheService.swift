import Foundation

final class CacheService {
    let urlCache: URLCache

    init(memoryMB: Int = 32, diskMB: Int = 256) {
        self.urlCache = URLCache(memoryCapacity: memoryMB * 1024 * 1024,
                                 diskCapacity: diskMB * 1024 * 1024,
                                 diskPath: "iWatch.URLCache")
    }

    static let `default` = CacheService()

    func clear() {
        urlCache.removeAllCachedResponses()
    }
}

func clearOnDeviceCaches(cacheService: CacheService) async {
    cacheService.clear()
    await clearImageCache()
}
