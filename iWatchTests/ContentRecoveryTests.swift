import Foundation
import Testing
@testable import iWatch

@Suite @MainActor
struct ContentRecoveryTests {
    @Test
    func failuresDoNotExposeProviderBodies() {
        let error = AppError.httpStatus(code: 503, message: "private-token-and-response")
        #expect(!UserFacingError.message(for: error).contains("private"))
        #expect(UserFacingError.message(for: URLError(.notConnectedToInternet)).contains("connection"))
        #expect(UserFacingError.message(for: AppError.rateLimited(retryAfter: 30)).contains("Wait"))
    }

    @Test
    func movieReloadFailureKeepsExistingLibraryAndCanRecover() async throws {
        let container = AppContainer.preview()
        let seeded = try await container.libraryRepository.movieLibraryItems()
        #expect(!seeded.isEmpty)
        let fails = TestValue(false)
        let model = MoviesScreenModel(repository: container.libraryRepository, session: container.session,
            loadItems: { _, _ in
                if fails.value { throw URLError(.notConnectedToInternet) }
                return seeded
            })
        await model.load(revision: 0)
        fails.value = true
        await model.load(revision: 1)
        #expect(model.items == seeded)
        #expect(model.errorText != nil)
        fails.value = false
        await model.load(revision: 1)
        #expect(model.errorText == nil)
    }

    @Test
    func showReloadFailureAndCancellationKeepExistingSnapshot() async throws {
        let container = AppContainer.preview()
        let seeded = try await container.libraryRepository.showLibrarySnapshot(revision: 0)
        #expect(!seeded.all.isEmpty)
        let failure = TestValue<Error?>(nil)
        let model = ShowsScreenModel(repository: container.libraryRepository, session: container.session,
            loadSnapshot: { _, _ in
                if let error = failure.value { throw error }
                return seeded
            })
        await model.load(revision: 0)
        failure.value = CancellationError()
        await model.load(revision: 1)
        #expect(model.snapshot == seeded)
        #expect(model.errorText == nil)
        failure.value = URLError(.timedOut)
        await model.load(revision: 1)
        #expect(model.snapshot == seeded)
        #expect(model.errorText != nil)
    }

    @Test
    func searchIgnoresLateResponsesForAnotherQuery() async throws {
        let container = AppContainer.preview()
        let model = SearchScreenModel(repository: container.libraryRepository, regionCode: "US", search: { query in
            if query == "old" { try await Task.sleep(for: .milliseconds(50)) }
            return [SearchItem(id: query == "old" ? 1 : 2, kind: .movie, title: query, posterPath: nil, year: nil)]
        })
        model.query = "old"
        let old = Task { await model.performSearch() }
        await Task.yield()
        model.query = "new"
        await model.performSearch()
        await old.value
        #expect(model.results.first?.title == "new")
    }

    @Test
    func failedSearchRetryKeepsOnlyResultsForThatQuery() async throws {
        let container = AppContainer.preview()
        let fails = TestValue(false)
        let item = SearchItem(id: 1, kind: .movie, title: "Movie", posterPath: nil, year: nil)
        let model = SearchScreenModel(repository: container.libraryRepository, regionCode: "US", search: { _ in
            if fails.value { throw URLError(.timedOut) }
            return [item]
        })
        model.query = "movie"
        await model.performSearch()
        fails.value = true
        await model.performSearch()
        #expect(model.results == [item])
        #expect(model.errorText != nil)
        model.query = "different"
        await model.performSearch()
        #expect(model.results.isEmpty)
    }
}

@MainActor
final class TestValue<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}
