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
    MetadataFreshnessStore().clear()
    await clearImageCache()
}

// Fetch freshness belongs to this device's cache, not to replicated library edits.
@MainActor
final class MetadataFreshnessStore {
    private let defaults: UserDefaults
    private static let key = "iWatch.metadataFetchDates"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func needsRefresh(_ resource: String, after interval: TimeInterval, now: Date = .now) -> Bool {
        let dates = defaults.dictionary(forKey: Self.key) as? [String: Double] ?? [:]
        if let attemptedAt = dates["attempt:" + resource], now.timeIntervalSince1970 - attemptedAt < 60 { return false }
        guard let fetchedAt = dates[resource] else { return true }
        return now.timeIntervalSince1970 < fetchedAt || now.timeIntervalSince1970 - fetchedAt >= interval
    }

    func markAttempt(_ resource: String) { markFetched("attempt:" + resource) }

    func markFetched(_ resource: String, now: Date = .now) {
        var dates = defaults.dictionary(forKey: Self.key) as? [String: Double] ?? [:]
        dates[resource] = now.timeIntervalSince1970
        if dates.count > 2048 {
            dates = Dictionary(uniqueKeysWithValues: dates.sorted { $0.value > $1.value }.prefix(2048).map { ($0.key, $0.value) })
        }
        defaults.set(dates, forKey: Self.key)
    }

    func clear() { defaults.removeObject(forKey: Self.key) }
}
