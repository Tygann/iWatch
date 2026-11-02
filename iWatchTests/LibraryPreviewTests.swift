import Foundation
import SwiftData
import Testing
@testable import iWatch

@Suite @MainActor
struct LibraryPreviewTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @Test
    func relaunchRestoresBothScreensAndRefreshReplacesPreview() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = AppContainer.preview()
        let repository = LibraryRepository(persistence: container.persistence, tmdb: container.tmdb,
            accountKeyProvider: { "account-a" }, previewStore: LibraryPreviewStore(directory: directory))
        let movies = try await repository.movieLibraryItems(revision: 0)
        let shows = try await repository.showLibrarySnapshot(revision: 0)
        #expect(!movies.isEmpty && !shows.all.isEmpty)

        // New repository and store instances simulate losing every in-memory cache.
        let reopened = LibraryRepository(persistence: container.persistence, tmdb: container.tmdb,
            accountKeyProvider: { "account-a" }, previewStore: LibraryPreviewStore(directory: directory))
        let pending = TestValue<CheckedContinuation<ShowLibrarySnapshot, Never>?>(nil)
        let showModel = ShowsScreenModel(repository: reopened, session: container.session,
            loadSnapshot: { _, _ in await withCheckedContinuation { pending.value = $0 } })
        let movieModel = MoviesScreenModel(repository: reopened, session: container.session,
            loadItems: { _, _ in [] })
        #expect(showModel.snapshot == shows)
        #expect(movieModel.items == movies)
        #expect(showModel.isShowingSavedSnapshot && movieModel.isShowingSavedSnapshot)
        let refresh = Task { await showModel.load(revision: 0) }
        while pending.value == nil { await Task.yield() }
        #expect(showModel.snapshot == shows)
        #expect(!showModel.isLoading)
        pending.value?.resume(returning: .empty)
        await refresh.value
        await movieModel.load(revision: 0)
        #expect(showModel.snapshot == .empty && movieModel.items.isEmpty)
        #expect(!showModel.isShowingSavedSnapshot && !movieModel.isShowingSavedSnapshot)
        // The saved view never counts as a loaded revision: revision zero still refreshes.
    }

    @Test
    func accountChangesAndLibraryReplacementRejectSavedTitles() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = AppContainer.preview()
        let store = LibraryPreviewStore(directory: directory)
        let repository = LibraryRepository(persistence: container.persistence, tmdb: container.tmdb,
            accountKeyProvider: { "account-a" }, previewStore: store)
        _ = try await repository.movieLibraryItems(revision: 0)
        _ = try await repository.showLibrarySnapshot(revision: 0)
        let otherAccount = LibraryRepository(persistence: container.persistence, tmdb: container.tmdb,
            accountKeyProvider: { "account-b" }, previewStore: store)
        #expect(otherAccount.savedMovieLibraryItems() == nil)
        #expect(otherAccount.savedShowLibrarySnapshot() == nil)

        _ = try await repository.movieLibraryItems(revision: 1, forceRefresh: true)
        _ = try await repository.showLibrarySnapshot(revision: 1, forceRefresh: true)
        let context = container.persistence.makeContext()
        LibraryGenerationPolicy.rotateGeneration(in: context)
        try context.save()
        #expect(repository.savedMovieLibraryItems() == nil)
        #expect(repository.savedShowLibrarySnapshot() == nil)
        // Even before the session publishes a new revision, old in-memory results
        // cannot leak across a generation change.
        #expect(try await repository.movieLibraryItems(revision: 1).isEmpty)
        #expect(try await repository.showLibrarySnapshot(revision: 1) == .empty)
        repository.invalidateSnapshots()
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("movies.json").path))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("shows.json").path))
    }

    @Test
    func invalidPreviewsFallBackWithoutTouchingLibrary() throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryPreviewStore(directory: directory)
        let scope = LibraryPreviewStore.Scope(generation: "one", accountKey: nil)
        let now = Date()
        store.saveMovies([], scope: scope, now: now)
        #expect(store.movies(scope: scope, now: now) == [])
        #expect(store.movies(scope: scope, now: now.addingTimeInterval(7 * 86400)) == nil)
        store.saveShows([], scope: scope, now: now.addingTimeInterval(60))
        #expect(store.shows(scope: scope, now: now) == nil)
        let url = directory.appendingPathComponent("movies.json")
        try Data("broken".utf8).write(to: url)
        #expect(store.movies(scope: scope) == nil)
        store.saveMovies([], scope: scope)
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["version"] = 999
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        #expect(store.movies(scope: scope) == nil)
        try Data(repeating: 0, count: 4 * 1024 * 1024 + 1).write(to: url)
        #expect(store.movies(scope: scope) == nil)
    }

    @Test
    func failedRefreshKeepsSavedTitlesAndOffersRecovery() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = AppContainer.preview()
        let repository = LibraryRepository(persistence: container.persistence, tmdb: container.tmdb,
            accountKeyProvider: { nil }, previewStore: LibraryPreviewStore(directory: directory))
        let saved = try await repository.showLibrarySnapshot(revision: 0)
        let model = ShowsScreenModel(repository: repository, session: container.session,
            loadSnapshot: { _, _ in throw CocoaError(.fileReadUnknown) })
        await model.load(revision: 0)
        #expect(model.snapshot == saved)
        #expect(model.isShowingSavedSnapshot)
        #expect(!model.isLoading && model.errorText != nil)
    }
}
