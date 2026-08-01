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
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let items = [
            makeShow(id: 1, bucket: .airing, nextAirDate: newer, nextEpisodeAirDate: older),
            makeShow(id: 2, bucket: .returning, nextAirDate: older, nextEpisodeAirDate: newer),
            makeShow(id: 3, bucket: .ended, nextAirDate: nil, nextEpisodeAirDate: nil)
        ]

        let snapshot = ShowLibrarySnapshot(items: items)

        #expect(snapshot.all.count == 3)
        #expect(snapshot.continueWatching.map(\.id) == [2, 1])
        #expect(snapshot.airing.map(\.id) == [1])
        #expect(snapshot.returning.map(\.id) == [2])
        #expect(snapshot.ended.map(\.id) == [3])
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
    nextEpisodeAirDate: Date?
) -> LibraryShowItem {
    LibraryShowItem(
        mediaID: MediaID(kind: .show, id: id),
        title: "Show \(id)",
        posterPath: "/\(id).jpg",
        status: ShowStatusSnapshot(bucket: bucket, nextAirDate: nextAirDate),
        progress: ShowProgress(
            watchedEpisodeKeys: [],
            watchedCount: nextEpisodeAirDate == nil ? 0 : 1,
            totalEpisodes: 10,
            remainingReleased: nextEpisodeAirDate == nil ? 0 : 1,
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
        needsProgressEnrichment: false
    )
}
