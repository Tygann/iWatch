import Foundation

@MainActor
final class ContentRepository {
    private let library: LibraryRepository

    init(library: LibraryRepository) {
        self.library = library
    }

    func details(for ref: MediaID, forceRefresh: Bool = false) async throws -> MediaDetails {
        try await library.mediaDetails(for: ref, forceRefresh: forceRefresh)
    }

    func cachedEpisodes(for showID: MediaID, seasonNumber: Int) async throws -> [EpisodeDetails] {
        try await library.cachedEpisodes(for: showID, seasonNumber: seasonNumber)
    }

    func episodes(for showID: MediaID, seasonNumber: Int, forceRefresh: Bool = false) async throws -> [EpisodeDetails] {
        try await library.episodes(for: showID, seasonNumber: seasonNumber, forceRefresh: forceRefresh)
    }

    func episodeDetails(
        for ref: EpisodeRef, forceRefresh: Bool = false, onCached: (EpisodeDetails) -> Void = { _ in }
    ) async throws -> EpisodeDetails {
        try await library.episodeDetails(for: ref, forceRefresh: forceRefresh, onCached: onCached)
    }

    func supplementaryDetails(for ref: MediaID, regionCode: String) async throws -> MediaSupplementaryDetails {
        try await library.supplementaryDetails(for: ref, regionCode: regionCode)
    }
}
