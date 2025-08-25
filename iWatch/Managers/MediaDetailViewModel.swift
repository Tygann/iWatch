// ViewModels/MediaDetailViewModel.swift
import SwiftUI
import Combine

@MainActor
final class MediaDetailViewModel: ObservableObject {

    // MARK: - View-facing adapter
    struct ViewData: Identifiable {
        struct Episode: Identifiable, Hashable {
            let id: Int
            let name: String
            let overview: String?
            let stillPath: String?
            let airDate: String?
            let dateAirDate: Date?
            let runtime: Int?
            let episodeNumber: Int
        }

        struct Season: Identifiable {
            let id: Int
            let seasonNumber: Int
            let name: String
            let posterPath: String?
            let episodeCount: Int?
            var episodes: [Episode] = []
        }

        let id: Int
        let title: String
        let tagline: String?
        let overview: String?
        let backdropPath: String?
        let posterPath: String?
        let releaseYear: String?
        let runtimeMinutes: Int?
        let rating: Double?
        let genres: [String]
        let isTV: Bool
        let seasons: [Season]
    }

    // MARK: - Source model + base states
    @Published private(set) var detail: MediaDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?

    /// Build the view adapter by projecting `detail` plus our per-season caches/states.
    var viewData: ViewData? { makeViewData() }

    /// Eagerly-fetched episodes keyed by `seasonNumber`
    private var allSeasonEpisodes: [Int: [ViewData.Episode]] = [:]

    // MARK: - Wiring
    private let env: AppEnvironment
    private let ref: MediaRef
    private var hasLoaded = false

    init(env: AppEnvironment, ref: MediaRef) {
        self.env = env
        self.ref = ref
    }

    // MARK: - Public API
    func load() async {
        guard !isLoading, !hasLoaded else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            switch ref.kind {
            case .movie:
                let dto = try await env.contentAPI.movieDetails(id: ref.id)
                self.detail = Self.mapMovieDetails(dto)

            case .tv:
                // 1) Fetch base TV details
                let dto = try await env.contentAPI.tvDetails(id: ref.id)
                let seasonNumbers = (dto.seasons ?? []).map { $0.seasonNumber }

                // 2) Fetch every season (and its episodes) concurrently
                var episodesMap: [Int: [ViewData.Episode]] = [:]
                try await withThrowingTaskGroup(of: (Int, [ViewData.Episode]).self) { group in
                    for s in seasonNumbers {
                        group.addTask {
                            // Requires ContentAPI to provide tvSeason(id:seasonNumber:)
                            let seasonDTO = try await self.env.contentAPI.tvSeason(id: self.ref.id, seasonNumber: s)
                            let eps: [ViewData.Episode] = seasonDTO.episodes.map { ep in
                                ViewData.Episode(
                                    id: ep.id,
                                    name: ep.name,
                                    overview: ep.overview,
                                    stillPath: ep.stillPath,
                                    airDate: ep.airDate,
                                    dateAirDate: ep.dateAirDate,
                                    runtime: ep.runtime,
                                    episodeNumber: ep.episodeNumber
                                )
                            }
                            return (s, eps)
                        }
                    }
                    for try await (s, eps) in group {
                        episodesMap[s] = eps
                    }
                }

                // 3) Map the TV details and stash the eager episodes
                self.detail = Self.mapTVDetails(dto)
                self.allSeasonEpisodes = episodesMap
            }
            hasLoaded = true
        } catch {
            if Self.isCancellation(error) { return }
            #if DEBUG
            print("Detail load failed for \(ref):", error)
            #endif
            self.errorText = "Couldn’t load details."
            self.detail = nil
        }
    }
    func refresh() async {
        hasLoaded = false
        allSeasonEpisodes.removeAll()
        await load()
    }
}

// MARK: - ViewData Projection
private extension MediaDetailViewModel {
    func makeViewData() -> ViewData? {
        guard let d = detail else { return nil }

        let seasonsVD: [ViewData.Season] = (d.seasons ?? []).map { s in
            var season = ViewData.Season(
                id: s.id,
                seasonNumber: s.seasonNumber,
                name: s.name,
                posterPath: s.posterPath,
                episodeCount: s.episodeCount
            )
            if let eps = allSeasonEpisodes[s.seasonNumber] {
                season.episodes = eps
            } else {
                season.episodes = []
            }
            return season
        }

        return ViewData(
            id: d.id,
            title: d.title,
            tagline: d.tagline,
            overview: d.overview,
            backdropPath: d.backdropPath,
            posterPath: d.posterPath,
            releaseYear: d.releaseYear,
            runtimeMinutes: d.runtimeMinutes,
            rating: d.rating,
            genres: d.genres,
            isTV: (d.kind == .tv),
            seasons: seasonsVD
        )
    }
}

// MARK: - Mappers (DTO -> Domain)
// These keep the VM lean. If you prefer, move them to a /Mappers folder.
private extension MediaDetailViewModel {
    static func mapMovieDetails(_ m: MovieDetailsDTO) -> MediaDetail {
        MediaDetail(
            id: m.id,
            kind: .movie,
            title: m.title,
            tagline: nonEmpty(m.tagline),
            overview: nonEmpty(m.overview),
            posterPath: m.posterPath ?? m.backdropPath,
            backdropPath: m.backdropPath,
            releaseYear: year(m.releaseDate),
            runtimeMinutes: m.runtime,
            genres: m.genres.map(\.name),
            rating: m.voteAverage,
            voteCount: m.voteCount,
            movieReleaseDate: m.releaseDate,
            numberOfSeasons: nil,
            numberOfEpisodes: nil,
            seasons: nil
        )
    }

    static func mapTVDetails(_ t: TVDetailsDTO) -> MediaDetail {
        MediaDetail(
            id: t.id,
            kind: .tv,
            title: t.name,
            tagline: nonEmpty(t.tagline),
            overview: nonEmpty(t.overview),
            posterPath: t.posterPath ?? t.backdropPath,
            backdropPath: t.backdropPath,
            releaseYear: year(t.firstAirDate),
            runtimeMinutes: t.episodeRunTime?.first,
            genres: t.genres.map(\.name),
            rating: t.voteAverage,
            voteCount: t.voteCount,
            movieReleaseDate: nil,
            numberOfSeasons: t.numberOfSeasons,
            numberOfEpisodes: t.numberOfEpisodes,
            seasons: t.seasons?.map {
                MediaDetail.Season(
                    id: $0.id,
                    name: nonEmpty($0.name) ?? "Season \($0.seasonNumber)",
                    seasonNumber: $0.seasonNumber,
                    posterPath: $0.posterPath,
                    episodeCount: $0.episodeCount
                )
            }
        )
    }
}

// MARK: - Utilities
private extension MediaDetailViewModel {
    static func year(_ s: String?) -> String? {
        guard let s, s.count >= 4 else { return nil }
        return String(s.prefix(4))
    }
    static func nonEmpty(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
    static func isCancellation(_ error: Error) -> Bool {
        if let u = error as? URLError, u.code == .cancelled { return true }
        return error is CancellationError
    }
}

// MARK: - Previews
extension MediaDetailViewModel {
    static var previewData: MediaDetailViewModel {
        let vm = MediaDetailViewModel(env: .preview, ref: MediaRef(id: 123, kind: .tv))
        vm.detail = MediaDetail(
            id: 123, kind: .tv, title: "Wednesday",
            tagline: "The wait has been torture.",
            overview: "Smart, sarcastic and a little dead inside, Wednesday Addams investigates twisted mysteries while making new friends — and foes — at Nevermore Academy.",
            posterPath: "/yueXS3q8BtoWekcHOATFHicLl3e.jpg",
            backdropPath: "/25g7mthXoJFcNZhAKz0evk17Bsx.jpg",
            releaseYear: "2022",
            runtimeMinutes: 52,
            genres: ["Sci‑Fi & Fantasy", "Mystery", "Comedy"],
            rating: 8.4,
            voteCount: 1432,
            movieReleaseDate: nil,
            numberOfSeasons: 2,
            numberOfEpisodes: 16,
            seasons: [
                .init(id: 1, name: "Season 1", seasonNumber: 1,
                      posterPath: "/8ByzyJ9vFevqHz7MKoPgRwhu9tC.jpg", episodeCount: 8),
                .init(id: 2, name: "Season 2", seasonNumber: 2,
                      posterPath: "/o4jyjFX6L7M92EcnbUAZ9ehOjq.jpg", episodeCount: 8)
            ]
        )
        // Seed preview with a couple of episode rows for Season 1
        vm.allSeasonEpisodes[1] = [
            .init(id: 111, name: "Episode One", overview: "Welcome to Nevermore.",
                  stillPath: nil, airDate: "2022-11-23", dateAirDate: Date(), runtime: 52, episodeNumber: 1),
            .init(id: 112, name: "Episode Two", overview: "Thing lends a hand.",
                  stillPath: nil, airDate: "2022-11-23", dateAirDate: Date(), runtime: 50, episodeNumber: 2)
        ]
        return vm
    }
}


















//// ViewModels/MediaDetailViewModel.swift
//import SwiftUI
//import Combine
//
//@MainActor
//final class MediaDetailViewModel: ObservableObject {
//
//    // MARK: View-facing adapter (keeps SwiftUI layer simple)
//    struct ViewData: Identifiable {
//        struct Season: Identifiable {
//            let id: Int
//            let seasonNumber: Int
//            let name: String
//            let posterPath: String?
//            let episodeCount: Int?
//        }
//        let id: Int
//        let title: String
//        let overview: String?
//        let backdropPath: String?
//        let posterPath: String?
//        let releaseYear: String?
//        let runtimeMinutes: Int?
//        let rating: Double?
//        let genres: [String]
//        let isTV: Bool
//        let seasons: [Season]
//
//        init(from d: MediaDetail) {
//            self.id = d.id
//            self.title = d.title
//            self.overview = d.overview
//            self.backdropPath = d.backdropPath
//            self.posterPath = d.posterPath
//            self.releaseYear = d.releaseYear
//            self.runtimeMinutes = d.runtimeMinutes
//            self.rating = d.rating
//            self.genres = d.genres
//            self.isTV = (d.kind == .tv)
//            self.seasons = (d.seasons ?? []).map {
//                .init(
//                    id: $0.id,
//                    seasonNumber: $0.seasonNumber,
//                    name: $0.name,
//                    posterPath: $0.posterPath,
//                    episodeCount: $0.episodeCount
//                )
//            }
//        }
//    }
//
//    // Source model + states
//    @Published var detail: MediaDetail?
//    @Published var isLoading = false
//    @Published var errorText: String?
//
//    // Adapter the view reads; nil while loading
//    var viewData: ViewData? { detail.map(ViewData.init) }
//
//    private let env: AppEnvironment
//    private let ref: MediaRef
//    private var hasLoaded = false
//
//    init(env: AppEnvironment, ref: MediaRef) {
//        self.env = env
//        self.ref = ref
//    }
//
//    func load() async {
//        guard !isLoading, !hasLoaded else { return }
//        isLoading = true
//        errorText = nil
//        defer { isLoading = false }
//
//        do {
//            switch ref.kind {
//            case .movie:
//                let m = try await env.contentAPI.movieDetails(id: ref.id)
//                detail = MediaDetail(
//                    id: m.id, kind: .movie, title: m.title,
//                    tagline: nonEmpty(m.tagline), overview: nonEmpty(m.overview),
//                    posterPath: m.posterPath ?? m.backdropPath, backdropPath: m.backdropPath,
//                    releaseYear: year(m.releaseDate), runtimeMinutes: m.runtime,
//                    genres: m.genres.map(\.name), rating: m.voteAverage, voteCount: m.voteCount,
//                    movieReleaseDate: m.releaseDate, numberOfSeasons: nil, numberOfEpisodes: nil, seasons: nil
//                )
//
//            case .tv:
//                let t = try await env.contentAPI.tvDetails(id: ref.id)
//                detail = MediaDetail(
//                    id: t.id, kind: .tv, title: t.name,
//                    tagline: nonEmpty(t.tagline), overview: nonEmpty(t.overview),
//                    posterPath: t.posterPath ?? t.backdropPath, backdropPath: t.backdropPath,
//                    releaseYear: year(t.firstAirDate), runtimeMinutes: t.episodeRunTime?.first,
//                    genres: t.genres.map(\.name), rating: t.voteAverage, voteCount: t.voteCount,
//                    movieReleaseDate: nil,
//                    numberOfSeasons: t.numberOfSeasons, numberOfEpisodes: t.numberOfEpisodes,
//                    seasons: t.seasons?.map {
//                        MediaDetail.Season(
//                            id: $0.id,
//                            name: nonEmpty($0.name) ?? "Season \($0.seasonNumber)",
//                            seasonNumber: $0.seasonNumber,
//                            posterPath: $0.posterPath,
//                            episodeCount: $0.episodeCount
//                        )
//                    }
//                )
//            }
//            hasLoaded = true
//
//        } catch {
//            if isCancellation(error) { return } // ignore cancellations
//            #if DEBUG
//            print("Detail load failed for \(ref):", error)
//            #endif
//            errorText = "Couldn’t load details."
//            detail = nil
//        }
//    }
//
//    // MARK: helpers
//    private func year(_ s: String?) -> String? {
//        guard let s, s.count >= 4 else { return nil }
//        return String(s.prefix(4))
//    }
//    private func nonEmpty(_ s: String?) -> String? {
//        guard let s else { return nil }
//        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
//        return t.isEmpty ? nil : t
//    }
//    private func isCancellation(_ error: Error) -> Bool {
//        if let u = error as? URLError, u.code == .cancelled { return true }
//        return error is CancellationError
//    }
//}
//
//extension MediaDetailViewModel {
//    static var previewData: MediaDetailViewModel {
//        let vm = MediaDetailViewModel(env: .preview, ref: MediaRef(id: 123, kind: .tv))
//        vm.detail = MediaDetail(
//            id: 123, kind: .tv, title: "Wednesday",
//            tagline: "The wait has been torture.",
//            overview: "Smart, sarcastic and a little dead inside, Wednesday Addams investigates twisted mysteries while making new friends — and foes — at Nevermore Academy.",
//            posterPath: "/yueXS3q8BtoWekcHOATFHicLl3e.jpg",
//            backdropPath: "/25g7mthXoJFcNZhAKz0evk17Bsx.jpg",
//            releaseYear: "2022",
//            runtimeMinutes: 52,
//            genres: ["Sci‑Fi & Fantasy", "Mystery", "Comedy"],
//            rating: 8.4,
//            voteCount: 1432,
//            movieReleaseDate: nil,
//            numberOfSeasons: 2,
//            numberOfEpisodes: 16,
//            seasons: [
//                .init(id: 1, name: "Season 1", seasonNumber: 1,
//                      posterPath: "/8ByzyJ9vFevqHz7MKoPgRwhu9tC.jpg", episodeCount: 8),
//                .init(id: 2, name: "Season 2", seasonNumber: 2,
//                      posterPath: "/o4jyjFX6L7M92EcnbUAZ9ehOjq.jpg", episodeCount: 8)
//            ]
//        )
//        return vm
//    }
//}























//// ViewModels/MediaDetailViewModel.swift
//import SwiftUI
//import Combine
//
//@MainActor
//final class MediaDetailViewModel: ObservableObject {
//    @Published var detail: MediaDetail?
//    @Published var isLoading = false
//    @Published var errorText: String?
//
//    private let env: AppEnvironment
//    private let ref: MediaRef
//    private var hasLoaded = false
//
//    init(env: AppEnvironment, ref: MediaRef) {
//        self.env = env
//        self.ref = ref
//    }
//
//    func load() async {
//        guard !isLoading, !hasLoaded else { return }
//        isLoading = true
//        errorText = nil
//        defer { isLoading = false }
//
//        do {
//            switch ref.kind {
//            case .movie:
//                let m = try await env.contentAPI.movieDetails(id: ref.id)
//                detail = MediaDetail(
//                    id: m.id, kind: .movie, title: m.title,
//                    tagline: nonEmpty(m.tagline), overview: nonEmpty(m.overview),
//                    posterPath: m.posterPath ?? m.backdropPath, backdropPath: m.backdropPath,
//                    releaseYear: year(m.releaseDate), runtimeMinutes: m.runtime,
//                    genres: m.genres.map(\.name), rating: m.voteAverage, voteCount: m.voteCount,
//                    movieReleaseDate: m.releaseDate, numberOfSeasons: nil, numberOfEpisodes: nil, seasons: nil
//                )
//            case .tv:
//                let t = try await env.contentAPI.tvDetails(id: ref.id)
//                detail = MediaDetail(
//                    id: t.id, kind: .tv, title: t.name,
//                    tagline: nonEmpty(t.tagline), overview: nonEmpty(t.overview),
//                    posterPath: t.posterPath ?? t.backdropPath, backdropPath: t.backdropPath,
//                    releaseYear: year(t.firstAirDate), runtimeMinutes: t.episodeRunTime?.first,
//                    genres: t.genres.map(\.name), rating: t.voteAverage, voteCount: t.voteCount,
//                    movieReleaseDate: nil,
//                    numberOfSeasons: t.numberOfSeasons, numberOfEpisodes: t.numberOfEpisodes,
//                    seasons: t.seasons?.map {
//                        MediaDetail.Season(
//                            id: $0.id,
//                            name: nonEmpty($0.name) ?? "Season \($0.seasonNumber)",
//                            seasonNumber: $0.seasonNumber,
//                            posterPath: $0.posterPath,
//                            episodeCount: $0.episodeCount
//                        )
//                    }
//                )
//            }
//            hasLoaded = true
//        } catch {
//            // Ignore cancellations (sheet toggles, fast re-renders, etc.)
//            if isCancellation(error) { return }
//            #if DEBUG
//            print("Detail load failed for \(ref):", error)
//            #endif
//            errorText = "Couldn’t load details."
//            detail = nil
//        }
//    }
//
//    // MARK: helpers
//    private func year(_ s: String?) -> String? {
//        guard let s, s.count >= 4 else { return nil }
//        return String(s.prefix(4))
//    }
//    private func nonEmpty(_ s: String?) -> String? {
//        guard let s else { return nil }
//        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
//        return t.isEmpty ? nil : t
//    }
//    private func isCancellation(_ error: Error) -> Bool {
//        if let u = error as? URLError, u.code == .cancelled { return true }
//        return error is CancellationError
//    }
//}
//
//extension MediaDetailViewModel {
//    static var previewData: MediaDetailViewModel {
//        // Use .preview for instant mock, or .previewSmart to pull real images if key exists
//        let vm = MediaDetailViewModel(env: .preview, ref: MediaRef(id: 123, kind: .tv))
//        vm.detail = MediaDetail(
//            id: 123,
//            kind: .tv,
//            title: "Wednesday",
//            tagline: "The wait has been torture.",
//            overview: "Smart, sarcastic and a little dead inside, Wednesday Addams investigates twisted mysteries while making new friends — and foes — at Nevermore Academy.",
//            posterPath: "/yueXS3q8BtoWekcHOATFHicLl3e.jpg",
//            backdropPath: "/25g7mthXoJFcNZhAKz0evk17Bsx.jpg",
//            releaseYear: "2022",
//            runtimeMinutes: 52,
//            genres: ["Sci‑Fi & Fantasy", "Mystery", "Comedy"],
//            rating: 8.4,
//            voteCount: 1432,
//            movieReleaseDate: nil,
//            numberOfSeasons: 2,
//            numberOfEpisodes: 16,
//            seasons: [
//                .init(id: 1, name: "Season 1", seasonNumber: 1,
//                      posterPath: "/8ByzyJ9vFevqHz7MKoPgRwhu9tC.jpg", episodeCount: 8),
//                .init(id: 2, name: "Season 2", seasonNumber: 2,
//                      posterPath: "/o4jyjFX6L7M92EcnbUAZ9ehOjq.jpg", episodeCount: 8)
//            ]
//        )
//        return vm
//    }
//}








//extension MediaDetailViewModel {
//    static var previewData: MediaDetailViewModel {
//        let vm = MediaDetailViewModel(env: .preview, ref: MediaRef(id: 123, kind: .tv))
//        vm.detail = MediaDetail(
//            id: 123,
//            kind: .tv,
//            title: "Wednesday",
//            tagline: "The wait has been torture.",
//            overview: "Smart, sarcastic and a little dead inside, Wednesday Addams investigates twisted mysteries while making new friends — and foes — at Nevermore Academy.",
//            posterPath: "/7JGm4ZpjzFV98HEoFv4bdUu1DHH.jpg",
//            backdropPath: "/uGy4DCmM33I7l86W7iCskNkvmLD.jpg",
//            releaseYear: "2022",
//            runtimeMinutes: 52,
//            genres: ["Sci-Fi & Fantasy", "Mystery", "Comedy"],
//            rating: 8.4,
//            voteCount: 1432,
//            movieReleaseDate: nil,
//            numberOfSeasons: 2,
//            numberOfEpisodes: 16,
//            seasons: [
//                MediaDetail.Season(
//                    id: 1,
//                    name: "Season 1",
//                    seasonNumber: 1,
//                    posterPath: "/8Dzyj9gFevqMh7bMdwRp0hu4tC.jpg",
//                    episodeCount: 8
//                ),
//                MediaDetail.Season(
//                    id: 2,
//                    name: "Season 2",
//                    seasonNumber: 2,
//                    posterPath: "/9dj1yF7K0l7XM8ZcNBuAZ09eHgQ.jpg",
//                    episodeCount: 8
//                )
//            ]
//        )
//        return vm
//    }
//}
