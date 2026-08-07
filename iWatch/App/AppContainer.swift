import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppContainer {
    let config: AppConfig
    let apiClient: APIClient
    let cacheService: CacheService
    let imageService: ImageService
    let persistence: Persistence
    let tmdb: TMDbService
    let trakt: TraktService
    let deviceIdentityStore: DeviceIdentityStore
    let libraryRepository: LibraryRepository
    let contentRepository: ContentRepository
    let peopleRepository: PeopleRepository
    let syncEngine: SyncEngine
    let session: AppSession
    let router: AppRouter
    private var hasLoadedTMDbSandboxCatalog = false

    init(config: AppConfig,
         apiClient: APIClient,
         cacheService: CacheService,
         imageService: ImageService,
         persistence: Persistence,
         tmdb: TMDbService,
         trakt: TraktService,
         deviceIdentityStore: DeviceIdentityStore,
         libraryRepository: LibraryRepository,
         contentRepository: ContentRepository,
         peopleRepository: PeopleRepository,
         syncEngine: SyncEngine,
         session: AppSession,
         router: AppRouter) {
        self.config = config
        self.apiClient = apiClient
        self.cacheService = cacheService
        self.imageService = imageService
        self.persistence = persistence
        self.tmdb = tmdb
        self.trakt = trakt
        self.deviceIdentityStore = deviceIdentityStore
        self.libraryRepository = libraryRepository
        self.contentRepository = contentRepository
        self.peopleRepository = peopleRepository
        self.syncEngine = syncEngine
        self.session = session
        self.router = router
    }

    static func bootstrap() -> AppContainer {
        if isRunningTests {
            return testHost()
        }

        if isRunningPreviews {
            return preview()
        }

        if ProcessInfo.processInfo.arguments.contains("UITEST_MODE") {
            return uiTest()
        }

        return live()
    }

    static func live() -> AppContainer {
        let config = AppConfig.load()
        let cacheService = CacheService.default
        let apiClient = APIClient.makeDefault(cacheService: cacheService)

        let imageService = ImageService()
        let persistence = Persistence()
        let tmdb = TMDbService(apiClient: apiClient, apiKey: config.tmdbKey)
        let trakt = TraktService(
            apiClient: apiClient,
            clientId: config.traktClientId,
            clientSecret: config.traktClientSecret,
            authStore: KeychainTraktAuthStore()
        )
        let deviceIdentityStore = KeychainDeviceIdentityStore()
        let resetGate = AppDataResetGate()
        let libraryRepository = LibraryRepository(persistence: persistence, tmdb: tmdb, resetGate: resetGate)
        let contentRepository = ContentRepository(library: libraryRepository)
        let peopleRepository = PeopleRepository(tmdb: tmdb)
        let syncEngine = SyncEngine(persistence: persistence, trakt: trakt, deviceIdentityStore: deviceIdentityStore, resetGate: resetGate)
        let cloudExportMonitor = CloudKitExportMonitor(containerIdentifier: "iCloud.com.tyler.iWatch")
        let session = AppSession(
            trakt: trakt,
            syncEngine: syncEngine,
            traktRedirectURI: config.traktRedirectURI,
            cacheService: cacheService,
            cloudExportMonitor: cloudExportMonitor
        )
        let router = AppRouter()

        return AppContainer(
            config: config,
            apiClient: apiClient,
            cacheService: cacheService,
            imageService: imageService,
            persistence: persistence,
            tmdb: tmdb,
            trakt: trakt,
            deviceIdentityStore: deviceIdentityStore,
            libraryRepository: libraryRepository,
            contentRepository: contentRepository,
            peopleRepository: peopleRepository,
            syncEngine: syncEngine,
            session: session,
            router: router
        )
    }

    static func testHost() -> AppContainer {
        let config = AppConfig.load()
        let cacheService = CacheService.default
        let apiClient = APIClient.makeDefault(cacheService: cacheService)

        let imageService = ImageService()
        let persistence = Persistence(
            inMemory: true,
            cloudKitDatabase: ModelConfiguration.CloudKitDatabase.none
        )
        let tmdb = TMDbService(apiClient: apiClient, apiKey: config.tmdbKey)
        let trakt = TraktService(
            apiClient: apiClient,
            clientId: config.traktClientId,
            clientSecret: config.traktClientSecret,
            authStore: InMemoryTraktAuthStore()
        )
        let deviceIdentityStore = PreviewDeviceIdentityStore()
        let resetGate = AppDataResetGate()
        let libraryRepository = LibraryRepository(persistence: persistence, tmdb: tmdb, resetGate: resetGate)
        let contentRepository = ContentRepository(library: libraryRepository)
        let peopleRepository = PeopleRepository(tmdb: tmdb)
        let syncEngine = SyncEngine(persistence: persistence, trakt: trakt, deviceIdentityStore: deviceIdentityStore, resetGate: resetGate)
        let cloudExportMonitor = ImmediateCloudExportMonitor()
        let session = AppSession(
            trakt: trakt,
            syncEngine: syncEngine,
            traktRedirectURI: config.traktRedirectURI,
            cacheService: cacheService,
            cloudExportMonitor: cloudExportMonitor
        )
        let router = AppRouter(defaultTab: 0)

        return AppContainer(
            config: config,
            apiClient: apiClient,
            cacheService: cacheService,
            imageService: imageService,
            persistence: persistence,
            tmdb: tmdb,
            trakt: trakt,
            deviceIdentityStore: deviceIdentityStore,
            libraryRepository: libraryRepository,
            contentRepository: contentRepository,
            peopleRepository: peopleRepository,
            syncEngine: syncEngine,
            session: session,
            router: router
        )
    }

    static func uiTest() -> AppContainer {
        let config = AppConfig.load()
        let cacheService = CacheService.default
        let apiClient = APIClient.makeDefault(cacheService: cacheService)

        let imageService = ImageService()
        let persistence = Persistence(
            inMemory: true,
            cloudKitDatabase: ModelConfiguration.CloudKitDatabase.none
        )
        let tmdb = TMDbService(apiClient: apiClient, apiKey: config.tmdbKey)
        let trakt = TraktService(
            apiClient: apiClient,
            clientId: config.traktClientId,
            clientSecret: config.traktClientSecret,
            authStore: InMemoryTraktAuthStore()
        )
        let deviceIdentityStore = PreviewDeviceIdentityStore()
        let resetGate = AppDataResetGate()
        let libraryRepository = LibraryRepository(persistence: persistence, tmdb: tmdb, resetGate: resetGate)
        let contentRepository = ContentRepository(library: libraryRepository)
        let peopleRepository = PeopleRepository(tmdb: tmdb)
        let syncEngine = SyncEngine(persistence: persistence, trakt: trakt, deviceIdentityStore: deviceIdentityStore, resetGate: resetGate)
        let cloudExportMonitor = ImmediateCloudExportMonitor()
        let session = AppSession(
            trakt: trakt,
            syncEngine: syncEngine,
            traktRedirectURI: config.traktRedirectURI,
            cacheService: cacheService,
            cloudExportMonitor: cloudExportMonitor
        )
        let router = AppRouter(defaultTab: 0)

        seedPreviewCatalog(into: persistence)

        return AppContainer(
            config: config,
            apiClient: apiClient,
            cacheService: cacheService,
            imageService: imageService,
            persistence: persistence,
            tmdb: tmdb,
            trakt: trakt,
            deviceIdentityStore: deviceIdentityStore,
            libraryRepository: libraryRepository,
            contentRepository: contentRepository,
            peopleRepository: peopleRepository,
            syncEngine: syncEngine,
            session: session,
            router: router
        )
    }

    static func preview(seedCatalog: Bool = true) -> AppContainer {
        let config = AppConfig.load()
        let cacheService = CacheService.default
        let apiClient = APIClient.makeDefault(cacheService: cacheService)

        let imageService = ImageService()
        let persistence = Persistence(
            inMemory: true,
            cloudKitDatabase: ModelConfiguration.CloudKitDatabase.none
        )
        let tmdb = TMDbService(apiClient: apiClient, apiKey: config.tmdbKey)
        let trakt = TraktService(
            apiClient: apiClient,
            clientId: config.traktClientId,
            clientSecret: config.traktClientSecret,
            authStore: InMemoryTraktAuthStore()
        )
        let deviceIdentityStore = PreviewDeviceIdentityStore()
        let resetGate = AppDataResetGate()
        let libraryRepository = LibraryRepository(persistence: persistence, tmdb: tmdb, resetGate: resetGate)
        let contentRepository = ContentRepository(library: libraryRepository)
        let peopleRepository = PeopleRepository(tmdb: tmdb)
        let syncEngine = SyncEngine(persistence: persistence, trakt: trakt, deviceIdentityStore: deviceIdentityStore, resetGate: resetGate)
        let cloudExportMonitor = ImmediateCloudExportMonitor()
        let session = AppSession(
            trakt: trakt,
            syncEngine: syncEngine,
            traktRedirectURI: config.traktRedirectURI,
            cacheService: cacheService,
            cloudExportMonitor: cloudExportMonitor
        )
        let router = AppRouter(defaultTab: 0)

        let container = AppContainer(
            config: config,
            apiClient: apiClient,
            cacheService: cacheService,
            imageService: imageService,
            persistence: persistence,
            tmdb: tmdb,
            trakt: trakt,
            deviceIdentityStore: deviceIdentityStore,
            libraryRepository: libraryRepository,
            contentRepository: contentRepository,
            peopleRepository: peopleRepository,
            syncEngine: syncEngine,
            session: session,
            router: router
        )
        if seedCatalog {
            seedPreviewCatalog(into: persistence)
        }
        return container
    }

    /// A Canvas-only, in-memory library backed by live TMDb discovery results.
    /// It intentionally has no Trakt credentials, CloudKit database, or durable store.
    static func tmdbSandboxPreview() -> AppContainer {
        preview(seedCatalog: false)
    }

    /// Loads a small, current TMDb catalog into the sandbox's ephemeral library.
    /// Safe to call from Canvas more than once.
    func loadTMDbSandboxCatalog() async -> String? {
        guard !hasLoadedTMDbSandboxCatalog else { return nil }
        hasLoadedTMDbSandboxCatalog = true

        do {
            async let movies = libraryRepository.trending(kind: .movie)
            async let shows = libraryRepository.trending(kind: .show)
            let items = try await (movies, shows)

            let context = persistence.makeContext()
            let now = Date()
            for item in Array(items.0.prefix(6)) + Array(items.1.prefix(6)) {
                let record = WatchlistRecord(
                    mediaID: item.mediaID,
                    isInWatchlist: true,
                    listedAt: now,
                    localUpdatedAt: now,
                    dirty: false
                )
                context.insert(record)
            }
            try context.save()
            session.markLibraryUpdated()
            return nil
        } catch {
            hasLoadedTMDbSandboxCatalog = false
            return error.localizedDescription
        }
    }
}

private actor PreviewDeviceIdentityStore: DeviceIdentityStore {
    func currentDeviceID() async -> String { "preview-device" }
}

private extension AppContainer {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var isRunningPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

@MainActor
private func seedPreviewCatalog(into persistence: Persistence) {
    let context = persistence.makeContext()

    let movie = MediaRecord(
        kind: .movie,
        tmdbID: 101,
        traktID: 1001,
        title: "UI Test Movie",
        overview: "A deterministic local movie used for UI smoke testing.",
        tagline: "Offline-first foundations",
        posterPath: "/ui-test-movie.jpg",
        backdropPath: "/ui-test-backdrop.jpg",
        rating: 8.4,
        ratingCount: 1240,
        genres: ["Drama", "Sci-Fi"],
        releaseDate: Calendar.current.date(from: DateComponents(year: 2024, month: 3, day: 1)),
        runtimeMinutes: 118
    )
    let watchedMovie = MediaRecord(
        kind: .movie,
        tmdbID: 102,
        traktID: 1002,
        title: "UI Test Watched Movie",
        posterPath: "/ui-test-watched-movie.jpg",
        releaseDate: Calendar.current.date(from: DateComponents(year: 2022, month: 8, day: 12)),
        runtimeMinutes: 104
    )
    let showSeasons = [
        StoredShowSeason(id: 201, traktID: 2001, seasonNumber: 1, name: "Season 1", episodeCount: 2, posterPath: "/ui-test-show-season-1.jpg")
    ]
    let seasonsData = try? JSONEncoder().encode(showSeasons)
    let show = MediaRecord(
        kind: .show,
        tmdbID: 202,
        traktID: 2002,
        title: "UI Test Show",
        overview: "A deterministic local show used for UI smoke testing.",
        tagline: "Watch progress without the network",
        posterPath: "/ui-test-show.jpg",
        backdropPath: "/ui-test-show-backdrop.jpg",
        rating: 7.8,
        ratingCount: 860,
        genres: ["Mystery", "Drama"],
        releaseDate: Calendar.current.date(from: DateComponents(year: 2023, month: 10, day: 1)),
        totalEpisodes: 2,
        nextAirDate: Calendar.current.date(byAdding: .day, value: 2, to: .now),
        statusRaw: "Returning Series",
        seasonsData: seasonsData
    )

    let episodes = [
        EpisodeRecord(
            showTMDbID: 202,
            showTraktID: 2002,
            tmdbID: 301,
            traktID: 3001,
            seasonNumber: 1,
            episodeNumber: 1,
            name: "Pilot",
            airDate: Calendar.current.date(byAdding: .day, value: -7, to: .now),
            stillPath: "/ui-test-episode-1.jpg",
            overview: "The first episode for UI testing."
        ),
        EpisodeRecord(
            showTMDbID: 202,
            showTraktID: 2002,
            tmdbID: 302,
            traktID: 3002,
            seasonNumber: 1,
            episodeNumber: 2,
            name: "Second Look",
            airDate: Calendar.current.date(byAdding: .day, value: -1, to: .now),
            stillPath: "/ui-test-episode-2.jpg",
            overview: "The second episode for UI testing."
        )
    ]

    let watchlist = [
        WatchlistRecord(mediaID: MediaID(kind: .movie, id: 101, traktID: 1001), isInWatchlist: true),
        WatchlistRecord(mediaID: MediaID(kind: .show, id: 202, traktID: 2002), isInWatchlist: true)
    ]

    let watchEvent = WatchedEventRecord(
        kind: .episode,
        tmdbID: 301,
        traktID: 3001,
        showTMDbID: 202,
        showTraktID: 2002,
        seasonNumber: 1,
        episodeNumber: 1,
        watchedAt: Calendar.current.date(byAdding: .day, value: -2, to: .now) ?? .now
    )
    let movieWatchEvent = WatchedEventRecord(
        kind: .movie,
        tmdbID: 102,
        traktID: 1002,
        watchedAt: Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .now
    )

    context.insert(movie)
    context.insert(watchedMovie)
    context.insert(show)
    episodes.forEach(context.insert(_:))
    watchlist.forEach(context.insert(_:))
    context.insert(watchEvent)
    context.insert(movieWatchEvent)
    try? context.save()
}
