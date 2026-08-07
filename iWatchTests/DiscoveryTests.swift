import Foundation
import Testing
@testable import iWatch

@Suite(.serialized)
struct DiscoveryTests {
    @Test
    func categoryCollectionsMatchMovieAndShowExpectations() {
        #expect(DiscoveryCollection.collections(for: .movie) == [.trending, .nowPlaying, .upcoming, .popular, .topRated])
        #expect(DiscoveryCollection.collections(for: .show) == [.trending, .airingThisWeek, .popular, .topRated])
    }

    @Test
    @MainActor
    func providerCatalogUsesRegionAndSortsByDisplayPriority() async throws {
        MockDiscoveryURLProtocol.handler = { request in
            #expect(request.url?.path == "/3/watch/providers/movie")
            #expect(request.url?.query?.contains("watch_region=GB") == true)
            let data = #"{"results":[{"provider_id":8,"provider_name":"Later","display_priority":3},{"provider_id":2,"provider_name":"First","logo_path":"/first.jpg","display_priority":1}]}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        defer { MockDiscoveryURLProtocol.handler = nil }

        let providers = try await makeDiscoveryService().watchProviders(kind: .movie, regionCode: "gb")

        #expect(providers.map(\.name) == ["First", "Later"])
        #expect(providers.first?.logoPath == "/first.jpg")
    }

    @Test
    @MainActor
    func providerDiscoveryRequestsStreamingOffersInTheSelectedRegion() async throws {
        MockDiscoveryURLProtocol.handler = { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            })
            #expect(request.url?.path == "/3/discover/tv")
            #expect(query["watch_region"] == "US")
            #expect(query["with_watch_providers"] == "8")
            #expect(query["with_watch_monetization_types"] == "flatrate|free|ads")
            let data = #"{"results":[{"id":42,"name":"Example Show","poster_path":"/show.jpg","first_air_date":"2026-01-01"}]}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        defer { MockDiscoveryURLProtocol.handler = nil }

        let items = try await makeDiscoveryService().discover(
            kind: .show,
            providerID: 8,
            offerType: .stream,
            regionCode: "US"
        )

        #expect(items.first?.title == "Example Show")
        #expect(items.first?.year == "2026")
        #expect(items.first?.kind == .show)
    }
}

private func makeDiscoveryService() -> TMDbService {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockDiscoveryURLProtocol.self]
    return TMDbService(apiClient: APIClient(session: URLSession(configuration: configuration)), apiKey: "test-key")
}

private final class MockDiscoveryURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
