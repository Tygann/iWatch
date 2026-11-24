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
    func continueWatchingKeepsPositionsAcrossProgressRefreshes() async throws {
        let container = AppContainer.preview()
        let item = try #require(try await container.libraryRepository.showLibrarySnapshot(revision: 0).continueWatching.first)
        let other = LibraryShowItem(mediaID: MediaID(kind: .show, id: 98765), title: "Other Show",
            posterPath: nil, status: item.status, progress: item.progress,
            isInWatchlist: item.isInWatchlist, disposition: item.disposition,
            listedAt: item.listedAt, lastWatchedAt: .distantFuture, needsProgressEnrichment: false)
        var loaded = ShowLibrarySnapshot(items: [item, other])
        let model = ShowsScreenModel(repository: container.libraryRepository, session: container.session,
            loadSnapshot: { _, _ in loaded })
        await model.load(revision: 0)
        #expect(model.continueWatchingItems.map(\.id) == [other.id, item.id])
        // A progress update moves this show to the front of the repository's sort.
        let updated = LibraryShowItem(mediaID: item.mediaID, title: item.title, posterPath: nil,
            status: item.status, progress: item.progress, isInWatchlist: item.isInWatchlist,
            disposition: item.disposition, listedAt: item.listedAt,
            lastWatchedAt: Date.distantFuture.addingTimeInterval(1), needsProgressEnrichment: false)
        loaded = ShowLibrarySnapshot(items: [updated, other])
        #expect(loaded.continueWatching.first?.id == item.id)
        await model.load(revision: 1)
        #expect(model.continueWatchingItems.map(\.id) == [other.id, item.id])
    }

    @Test
    func quickWatchReturnsOnlyItsOwnEventForUndo() async throws {
        let container = AppContainer.preview()
        let repository = container.libraryRepository
        let snapshot = try await repository.showLibrarySnapshot(revision: 0)
        let item = try #require(snapshot.continueWatching.first)
        let next = try #require(item.progress.nextEpisode)
        let id = MediaID(kind: .episode, id: next.tmdbID, traktID: next.traktID)
        let created = try #require(try await repository.addWatchEvent(for: id, watchedAt: .now, allowRewatch: false))
        let duplicate = try await repository.addWatchEvent(for: id, watchedAt: .now, allowRewatch: false)
        #expect(duplicate == nil)
        let rewatch = try #require(try await repository.addWatchEvent(for: id, watchedAt: Date().addingTimeInterval(60)))
        try await repository.removeWatchEvent(eventID: created)
        #expect(await repository.latestWatchEventID(for: id) == rewatch)
    }

    @Test
    func adjacentReleasedEpisodesIncludeWatchedAndCrossSeasons() async throws {
        let container = AppContainer.preview()
        let context = container.persistence.makeContext()
        let show = 90001
        let rows = [
            EpisodeRecord(showTMDbID: show, tmdbID: 90011, seasonNumber: 1, episodeNumber: 1,
                name: "Earlier gap", airDate: .distantPast),
            EpisodeRecord(showTMDbID: show, tmdbID: 90012, seasonNumber: 1, episodeNumber: 2,
                name: "Current", airDate: .distantPast),
            EpisodeRecord(showTMDbID: show, tmdbID: 90013, seasonNumber: 1, episodeNumber: 3,
                name: "Already watched", airDate: .distantPast),
            EpisodeRecord(showTMDbID: show, tmdbID: 90021, seasonNumber: 2, episodeNumber: 1,
                name: "Next season", airDate: .distantPast),
            EpisodeRecord(showTMDbID: show, tmdbID: 90022, seasonNumber: 2, episodeNumber: 2,
                name: "Future", airDate: .distantFuture)
        ]
        rows.forEach(context.insert(_:))
        try context.save()
        try await container.libraryRepository.addWatchEvent(for: MediaID(kind: .episode, id: 90013), watchedAt: .now)
        let adjacent = try container.libraryRepository.adjacentReleasedEpisodes(to:
            EpisodeRef(showId: show, season: 1, episode: 2))
        #expect(adjacent.previous?.id == 90011)
        #expect(adjacent.next?.id == 90013)
        let boundary = try container.libraryRepository.adjacentReleasedEpisodes(to:
            EpisodeRef(showId: show, season: 2, episode: 1))
        #expect(boundary.previous?.id == 90013)
        #expect(boundary.next == nil)
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
    func quickWatchConfirmsSaveBeforeRefreshingTheShow() async throws {
        let container = AppContainer.preview()
        let repository = container.libraryRepository
        let saved = try await repository.showLibrarySnapshot(revision: 0)
        let item = try #require(saved.continueWatching.first)
        let episode = try #require(item.progress.nextEpisode)
        let model = ShowsScreenModel(repository: repository, session: container.session) { _, _ in
            Issue.record("Quick watch should update the show without waiting for the full library.")
            return saved
        }
        model.snapshot = saved

        var didConfirm = false
        await model.markNextEpisodeWatched(for: item) {
            didConfirm = true
            #expect(model.snapshot.continueWatching.first?.progress.nextEpisode == episode)
        }

        #expect(didConfirm)
        let updated = try #require(model.snapshot.all.first { $0.id == item.id })
        #expect(updated.progress.watchedCount == item.progress.watchedCount + 1)
        #expect(updated.progress.nextEpisode != episode)
        let full = try await repository.showLibrarySnapshot(revision: container.session.libraryRevision)
        #expect(updated == full.all.first { $0.id == item.id })
    }

    @Test
    func cachedMarkWatchedDoesNotDuplicateAnAlreadyWatchedEpisode() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = AppContainer.preview()
        let repository = LibraryRepository(persistence: container.persistence, tmdb: container.tmdb,
            deviceIdentityStore: container.deviceIdentityStore,
            accountKeyProvider: { nil }, previewStore: LibraryPreviewStore(directory: directory))
        let saved = try await repository.showLibrarySnapshot(revision: 0)
        let item = try #require(saved.continueWatching.first)
        let next = try #require(item.progress.nextEpisode)
        let episode = MediaID(kind: .episode, id: next.tmdbID, traktID: next.traktID)
        // Another device/local action has watched the episode since the preview was saved.
        try await repository.addWatchEvent(for: episode, watchedAt: Date().addingTimeInterval(-60))
        let model = ShowsScreenModel(repository: repository, session: container.session)
        #expect(model.isShowingSavedSnapshot)
        await model.markNextEpisodeWatched(for: item)
        let events = try container.persistence.makeContext().fetch(FetchDescriptor<WatchedEventRecord>())
        #expect(events.filter { $0.tmdbID == episode.tmdbID && !$0.tombstoned }.count == 1)
        #expect(model.snapshot.continueWatching.isEmpty)
        // Explicit rewatch remains available and still records an additional play.
        try await repository.addWatchEvent(for: episode, watchedAt: Date().addingTimeInterval(60))
        let afterRewatch = try container.persistence.makeContext().fetch(FetchDescriptor<WatchedEventRecord>())
        #expect(afterRewatch.filter { $0.tmdbID == episode.tmdbID && !$0.tombstoned }.count == 2)
    }

    @Test
    func cachedMovieMarkWatchedIsIdempotentButExplicitRewatchIsPreserved() async throws {
        let container = AppContainer.preview()
        let item = try #require(try await container.libraryRepository.movieLibraryItems().first(where: { $0.isInWatchlist }))
        try await container.libraryRepository.addWatchEvent(for: item.mediaID, watchedAt: Date().addingTimeInterval(-60))
        let model = MoviesScreenModel(repository: container.libraryRepository, session: container.session)
        await model.markWatched(item)
        var events = try container.persistence.makeContext().fetch(FetchDescriptor<WatchedEventRecord>())
        #expect(events.filter { $0.tmdbID == item.mediaID.tmdbID && !$0.tombstoned }.count == 1)
        let watched = try #require(model.items.first(where: { $0.id == item.id }))
        await model.markWatched(watched)
        events = try container.persistence.makeContext().fetch(FetchDescriptor<WatchedEventRecord>())
        #expect(events.filter { $0.tmdbID == item.mediaID.tmdbID && !$0.tombstoned }.count == 2)
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
