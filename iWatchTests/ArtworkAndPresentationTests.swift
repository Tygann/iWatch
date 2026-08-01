import Foundation
import Testing
import UIKit
@testable import iWatch

@Suite(.serialized)
struct ArtworkAndPresentationTests {
    @Test
    func artworkLoaderDownsamplesAndReusesDecodedImage() async throws {
        let sourceData = try #require(makeTestImage(size: CGSize(width: 600, height: 900)).pngData())
        let url = try #require(URL(string: "https://example.com/poster.png"))
        MockArtworkURLProtocol.responseData = sourceData
        MockArtworkURLProtocol.requestCount = 0
        defer { MockArtworkURLProtocol.responseData = nil }

        let loader = ArtworkLoader(
            diskCapacity: 0,
            protocolClasses: [MockArtworkURLProtocol.self],
            decodedImages: ArtworkMemoryCache(memoryCapacity: 4 * 1_024 * 1_024)
        )
        let first = await loader.image(
            for: url,
            targetSize: CGSize(width: 100, height: 150),
            displayScale: 2
        )
        let second = await loader.image(
            for: url,
            targetSize: CGSize(width: 100, height: 150),
            displayScale: 2
        )

        #expect(first?.cgImage?.width == 200)
        #expect(first?.cgImage?.height == 300)
        #expect(second != nil)
        #expect(MockArtworkURLProtocol.requestCount == 1)
    }

    @Test
    func artworkLoaderDeduplicatesConcurrentRequestsAndClearEvictsMemory() async throws {
        let sourceData = try #require(makeTestImage(size: CGSize(width: 200, height: 300)).jpegData(compressionQuality: 0.8))
        let url = try #require(URL(string: "https://example.com/shared.jpg"))
        MockArtworkURLProtocol.responseData = sourceData
        MockArtworkURLProtocol.requestCount = 0
        MockArtworkURLProtocol.delay = 0.05
        defer {
            MockArtworkURLProtocol.responseData = nil
            MockArtworkURLProtocol.delay = 0
        }

        let loader = ArtworkLoader(
            diskCapacity: 0,
            protocolClasses: [MockArtworkURLProtocol.self],
            decodedImages: ArtworkMemoryCache(memoryCapacity: 4 * 1_024 * 1_024)
        )
        async let first = loader.image(for: url, targetSize: CGSize(width: 100, height: 150), displayScale: 2)
        async let second = loader.image(for: url, targetSize: CGSize(width: 100, height: 150), displayScale: 2)
        #expect(await first != nil)
        #expect(await second != nil)
        #expect(MockArtworkURLProtocol.requestCount == 1)

        await loader.clear()
        #expect(await loader.image(for: url, targetSize: CGSize(width: 100, height: 150), displayScale: 2) != nil)
        #expect(MockArtworkURLProtocol.requestCount == 2)
    }

    @Test
    func showSnapshotPrecomputesSectionsAndOrdering() {
        let today = Date(timeIntervalSince1970: 1_000_000)
        let tomorrow = today.addingTimeInterval(86_400)
        let later = tomorrow.addingTimeInterval(86_400)
        let items = [
            makeShow(id: 1, bucket: .airing, nextAirDate: later, nextEpisodeAirDate: today, watchedCount: 1),
            makeShow(id: 2, bucket: .returning, nextAirDate: tomorrow, nextEpisodeAirDate: later, watchedCount: 1),
            makeShow(id: 3, bucket: .ended, nextAirDate: nil, nextEpisodeAirDate: nil, watchedCount: 10, remainingReleased: 0, totalEpisodes: 10),
            makeShow(id: 4, bucket: .returning, nextAirDate: nil, nextEpisodeAirDate: nil, watchedCount: 4, remainingReleased: 0),
            makeShow(id: 5, bucket: .ended, nextAirDate: nil, nextEpisodeAirDate: today, watchedCount: 0)
        ]

        let snapshot = ShowLibrarySnapshot(items: items, referenceDate: today)

        #expect(snapshot.all.count == 5)
        #expect(snapshot.continueWatching.map(\.id) == [2, 1])
        #expect(snapshot.comingUp.map(\.id) == [2, 1])
        #expect(snapshot.watchlist.map(\.id) == [5])
        #expect(snapshot.caughtUp.map(\.id) == [4])
        #expect(snapshot.completed.map(\.id) == [3])
    }

    @Test
    func showSnapshotUsesPurposeDrivenOrdering() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let items = [
            makeShow(id: 10, bucket: .returning, nextAirDate: nil, nextEpisodeAirDate: now, lastWatchedAt: now),
            makeShow(id: 11, bucket: .returning, nextAirDate: nil, nextEpisodeAirDate: now, lastWatchedAt: now.addingTimeInterval(10)),
            makeShow(id: 12, bucket: .returning, nextAirDate: nil, nextEpisodeAirDate: nil, watchedCount: 0, listedAt: now),
            makeShow(id: 13, bucket: .returning, nextAirDate: nil, nextEpisodeAirDate: nil, watchedCount: 0, listedAt: now.addingTimeInterval(10)),
            makeShow(id: 14, bucket: .ended, nextAirDate: nil, nextEpisodeAirDate: nil, watchedCount: 10, remainingReleased: 0, totalEpisodes: 10, lastWatchedAt: now),
            makeShow(id: 15, bucket: .ended, nextAirDate: nil, nextEpisodeAirDate: nil, watchedCount: 10, remainingReleased: 0, totalEpisodes: 10, lastWatchedAt: now.addingTimeInterval(10)),
            makeShow(id: 16, bucket: .returning, nextAirDate: now.addingTimeInterval(200), nextEpisodeAirDate: nil, watchedCount: 2, remainingReleased: 0),
            makeShow(id: 17, bucket: .returning, nextAirDate: now.addingTimeInterval(100), nextEpisodeAirDate: nil, watchedCount: 2, remainingReleased: 0)
        ]

        let snapshot = ShowLibrarySnapshot(items: items, referenceDate: now)

        #expect(snapshot.continueWatching.map(\.id) == [11, 10])
        #expect(snapshot.watchlist.map(\.id) == [13, 12])
        #expect(snapshot.completed.map(\.id) == [15, 14])
        #expect(snapshot.caughtUp.map(\.id) == [17, 16])
    }

    @Test
    func showStatusUsesConciseDisplayNames() {
        #expect(makeShowDetails(status: "Returning Series").showStatusDisplayName == "Returning")
        #expect(makeShowDetails(status: "Cancelled").showStatusDisplayName == "Canceled")
        #expect(makeShowDetails(status: "Ended").showStatusDisplayName == "Ended")
        #expect(makeShowDetails(status: "In Production").showStatusDisplayName == "In Production")
        #expect(makeShowDetails(status: "Custom Status").showStatusDisplayName == "Custom Status")
        #expect(makeShowDetails(status: "   ").showStatusDisplayName == nil)
    }

    @Test
    func artworkKindsUseTMDbSizesAppropriateForTheirContent() throws {
        let path = "/sample.jpg"
        let still = try #require(ImageURLBuilder.make(path, size: .episodeStill))
        let profile = try #require(ImageURLBuilder.make(path, size: .profile))

        #expect(still.path.contains("/w300/"))
        #expect(profile.path.contains("/h632/"))
    }

    @Test
    func decodedMemoryCacheSupportsSynchronousReuseAndClear() {
        let cache = ArtworkMemoryCache(memoryCapacity: 1_024 * 1_024)
        let image = makeTestImage(size: CGSize(width: 20, height: 20))

        cache.insert(image, forKey: "poster")
        #expect(cache.image(forKey: "poster") != nil)

        cache.clear()
        #expect(cache.image(forKey: "poster") == nil)
    }

    @Test
    func progressEnrichmentOnlyRunsForIncompleteSeasonCaches() {
        let seasons = [
            StoredShowSeason(
                id: 1,
                traktID: nil,
                seasonNumber: 1,
                name: "Season 1",
                episodeCount: 10,
                posterPath: nil
            )
        ]

        #expect(LibraryProgressEnrichmentPolicy.needsEnrichment(
            seasons: seasons,
            cachedEpisodeCounts: [1: 4]
        ))
        #expect(!LibraryProgressEnrichmentPolicy.needsEnrichment(
            seasons: seasons,
            cachedEpisodeCounts: [1: 10]
        ))
    }

    @Test
    func partialOrArtworkIncompleteSeasonCachesRefreshOnce() {
        #expect(EpisodeSeasonCachePolicy.shouldRefresh(
            cachedCount: 3,
            expectedEpisodeCount: 7,
            hasMissingArtwork: false,
            attemptedArtworkRefresh: false
        ))
        #expect(EpisodeSeasonCachePolicy.shouldRefresh(
            cachedCount: 10,
            expectedEpisodeCount: 10,
            hasMissingArtwork: true,
            attemptedArtworkRefresh: false
        ))
        #expect(!EpisodeSeasonCachePolicy.shouldRefresh(
            cachedCount: 10,
            expectedEpisodeCount: 10,
            hasMissingArtwork: true,
            attemptedArtworkRefresh: true
        ))
        #expect(!EpisodeSeasonCachePolicy.shouldRefresh(
            cachedCount: 10,
            expectedEpisodeCount: 10,
            hasMissingArtwork: false,
            attemptedArtworkRefresh: false
        ))
    }
}

private final class MockArtworkURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseData: Data?
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var delay: TimeInterval = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        if Self.delay > 0 { Thread.sleep(forTimeInterval: Self.delay) }
        guard let data = Self.responseData,
              let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/jpeg"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeTestImage(size: CGSize) -> UIImage {
    UIGraphicsImageRenderer(size: size).image { context in
        UIColor.systemBlue.setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
}

private func makeShow(
    id: Int,
    bucket: ShowStatusSnapshot.Bucket,
    nextAirDate: Date?,
    nextEpisodeAirDate: Date?,
    watchedCount: Int = 1,
    remainingReleased: Int? = nil,
    totalEpisodes: Int = 10,
    listedAt: Date? = nil,
    lastWatchedAt: Date? = nil
) -> LibraryShowItem {
    LibraryShowItem(
        mediaID: MediaID(kind: .show, id: id),
        title: "Show \(id)",
        posterPath: "/\(id).jpg",
        status: ShowStatusSnapshot(bucket: bucket, nextAirDate: nextAirDate),
        progress: ShowProgress(
            watchedEpisodeKeys: [],
            watchedCount: watchedCount,
            totalEpisodes: totalEpisodes,
            remainingReleased: remainingReleased ?? (nextEpisodeAirDate == nil ? 0 : 1),
            nextEpisode: nextEpisodeAirDate.map {
                ShowProgress.NextEpisode(
                    tmdbID: id * 100,
                    traktID: nil,
                    season: 1,
                    episode: 2,
                    airDate: $0
                )
            }
        ),
        listedAt: listedAt ?? Date(timeIntervalSince1970: TimeInterval(id)),
        lastWatchedAt: lastWatchedAt ?? Date(timeIntervalSince1970: TimeInterval(id)),
        needsProgressEnrichment: false
    )
}

private func makeShowDetails(status: String?) -> MediaDetails {
    .show(
        ShowDetails(
            common: MediaCommon(
                id: 1,
                traktID: nil,
                title: "Show",
                overview: nil,
                tagline: nil,
                posterPath: nil,
                backdropPath: nil,
                rating: nil,
                ratingCount: nil,
                genres: [],
                releaseDate: nil
            ),
            seasons: [],
            totalEpisodes: nil,
            nextAirDate: nil,
            status: status
        )
    )
}
