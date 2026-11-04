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
    func olderShowLoadCannotReplaceNewerLibrary() async throws {
        let container = AppContainer.preview()
        let seeded = try await container.libraryRepository.showLibrarySnapshot(revision: 0)
        let pending = TestValue<CheckedContinuation<ShowLibrarySnapshot, Never>?>(nil)
        let model = ShowsScreenModel(repository: container.libraryRepository, session: container.session,
            loadSnapshot: { revision, _ in
                if revision == 0 {
                    return await withCheckedContinuation { pending.value = $0 }
                }
                return seeded
            })
        let older = Task { await model.load(revision: 0) }
        while pending.value == nil { await Task.yield() }
        await model.load(revision: 1)
        #expect(model.snapshot == seeded)
        pending.value?.resume(returning: .empty)
        await older.value
        #expect(model.snapshot == seeded)
        #expect(!model.isLoading)
    }

    @Test
    func olderMovieLoadCannotReplaceNewerLibrary() async throws {
        let container = AppContainer.preview()
        let seeded = try await container.libraryRepository.movieLibraryItems()
        let pending = TestValue<CheckedContinuation<[LibraryMovieItem], Never>?>(nil)
        let model = MoviesScreenModel(repository: container.libraryRepository, session: container.session,
            loadItems: { revision, _ in
                if revision == 0 {
                    return await withCheckedContinuation { pending.value = $0 }
                }
                return seeded
            })
        let older = Task { await model.load(revision: 0) }
        while pending.value == nil { await Task.yield() }
        await model.load(revision: 1)
        pending.value?.resume(returning: [])
        await older.value
        #expect(model.items == seeded)
        #expect(!model.isLoading)
    }

    @Test(arguments: [false, true])
    func cachedSeasonAppearsBeforeRefreshCompletes(fails: Bool) async throws {
        let container = AppContainer.preview()
        let showID = MediaID(kind: .show, id: 202, traktID: 2002)
        let cached = try container.contentRepository.cachedEpisodes(for: showID, seasonNumber: 1)
        #expect(!cached.isEmpty)
        let pending = TestValue<CheckedContinuation<[EpisodeDetails], Error>?>(nil)
        let model = MediaDetailScreenModel(ref: showID, contentRepository: container.contentRepository,
            libraryRepository: container.libraryRepository, session: container.session,
            loadEpisodes: { _, _, _ in
                try await withCheckedThrowingContinuation { pending.value = $0 }
            })
        model.loadState = .loaded(try await container.contentRepository.details(for: showID))
        let refresh = Task { await model.loadSeason(1) }
        while pending.value == nil { await Task.yield() }
        #expect(model.loadingSeasons.contains(1))
        #expect(model.episodesBySeason[1] == cached)
        if fails { pending.value?.resume(throwing: URLError(.notConnectedToInternet)) }
        else { pending.value?.resume(returning: Array(cached.prefix(1))) }
        await refresh.value
        #expect(model.episodesBySeason[1] == (fails ? cached : Array(cached.prefix(1))))
        #expect((model.operationError != nil) == fails)
        #expect(model.loadingSeasons.isEmpty)
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
