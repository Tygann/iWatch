import Foundation

enum TMDbMappers {
    static func movie(_ dto: TMDbMovieDetailsDTO) -> MovieDetails {
        let common = MediaCommon(
            id: dto.id,
            traktID: nil,
            title: dto.title,
            overview: dto.overview,
            tagline: dto.tagline,
            posterPath: dto.posterPath,
            backdropPath: dto.backdropPath,
            rating: dto.voteAverage,
            ratingCount: dto.voteCount,
            genres: dto.genres.map(\.name),
            releaseDate: parseISODate(dto.releaseDate)
//            releaseYear: dto.releaseDate.flatMap { String($0.prefix(4)) }
        )
        return MovieDetails(common: common, runtimeMinutes: dto.runtime)
    }

    static func show(_ dto: TMDbShowDetailsDTO) -> ShowDetails {
        let common = MediaCommon(
            id: dto.id,
            traktID: nil,
            title: dto.name,
            overview: dto.overview,
            tagline: dto.tagline,
            posterPath: dto.posterPath,
            backdropPath: dto.backdropPath,
            rating: dto.voteAverage,
            ratingCount: dto.voteCount,
            genres: dto.genres.map(\.name),
            releaseDate: parseISODate(dto.firstAirDate)
//            releaseYear: dto.firstAirDate.flatMap { String($0.prefix(4)) }
        )

        let seasons = dto.seasons.map {
            ShowDetails.Season(
                id: $0.id,
                traktID: nil,
                seasonNumber: $0.seasonNumber,
                name: $0.name,
                episodeCount: $0.episodeCount,
                posterPath: $0.posterPath
            )
        }
        return ShowDetails(common: common,
                           seasons: seasons,
                           totalEpisodes: dto.numberOfEpisodes,
                           nextAirDate: parseISODate(dto.nextEpisodeToAir?.airDate),
                           status: dto.status)
    }

    static func episode(_ dto: TMDbEpisodeDTO, showId: Int, showTraktID: Int? = nil) -> EpisodeDetails {
        var details = EpisodeDetails(
            id: dto.id,
            traktID: nil,
            showId: showId,
            showTraktID: showTraktID,
            seasonNumber: dto.seasonNumber,
            episodeNumber: dto.episodeNumber,
            name: dto.name,
            airDate: dto.airDate,
            stillPath: dto.stillPath,
            overview: dto.overview
        )

        let hasRichBlocks =
            dto.credits != nil || dto.images != nil || dto.videos != nil || dto.externalIds != nil ||
            dto.runtime != nil || dto.productionCode != nil || dto.voteAverage != nil || dto.voteCount != nil

        guard hasRichBlocks else { return details }

        func creditFromCrew(_ c: TMDbEpisodeDTO.Crew) -> EpisodeDetails.Extras.Credit {
            .init(id: c.id, name: c.name, role: nil, job: c.job, profilePath: c.profilePath, order: nil)
        }
        func creditFromGuest(_ g: TMDbEpisodeDTO.Guest) -> EpisodeDetails.Extras.Credit {
            .init(id: g.id, name: g.name, role: g.character, job: nil, profilePath: g.profilePath, order: nil)
        }
        func creditFromCast(_ c: TMDbEpisodeDTO.Cast) -> EpisodeDetails.Extras.Credit {
            .init(id: c.id, name: c.name, role: c.character, job: nil, profilePath: c.profilePath, order: c.order)
        }

        let directors = (dto.credits?.crew ?? []).filter { ($0.job ?? "").caseInsensitiveCompare("Director") == .orderedSame }.map(creditFromCrew)
        let writers   = (dto.credits?.crew ?? []).filter {
            guard let j = $0.job?.lowercased() else { return false }
            return j == "writer" || j == "screenplay" || j == "teleplay"
        }.map(creditFromCrew)

        let cast      = (dto.credits?.cast ?? []).map(creditFromCast)
        let guests    = (dto.credits?.guestStars ?? []).map(creditFromGuest)
        let crewAll   = (dto.credits?.crew ?? []).map(creditFromCrew)

        let images    = (dto.images?.stills ?? []).compactMap { $0.filePath }
        let videos    = (dto.videos?.results ?? []).map {
            EpisodeDetails.Extras.Video(id: $0.id, key: $0.key, name: $0.name, site: $0.site, type: $0.type)
        }
        let exIDs     = EpisodeDetails.Extras.ExternalIDs(
            imdb: dto.externalIds?.imdbId,
            tvdb: dto.externalIds?.tvdbId,
            facebook: dto.externalIds?.facebookId,
            instagram: dto.externalIds?.instagramId,
            twitter: dto.externalIds?.twitterId
        )

        details.extras = .init(
            seasonNumber: dto.seasonNumber,
            runtime: dto.runtime,
            voteAverage: dto.voteAverage,
            voteCount: dto.voteCount,
            productionCode: dto.productionCode,
            cast: cast,
            directors: directors,
            writers: writers,
            guestStars: guests,
            crew: crewAll,
            images: images,
            videos: videos,
            externalIDs: exIDs
        )
        return details
    }

    static func person(_ d: TMDbPersonDetailsDTO) -> PersonDetails {
        let refs: [MediaRef] = (d.combinedCredits?.cast ?? []).compactMap { c in
            guard let id = c.id else { return nil }
            if c.mediaType == "movie" { return MediaRef(kind: .movie, id: id) }
            if c.mediaType == "tv" { return MediaRef(kind: .show, id: id) }
            return nil
        }
        return PersonDetails(id: d.id, name: d.name, biography: d.biography, profilePath: d.profilePath, knownFor: Array(refs.prefix(12)))
    }

    static func searchItem(_ dto: TMDbMultiSearchItemDTO) -> SearchItem? {
        let kind: MediaKind
        switch dto.mediaType {
        case "movie":
            kind = .movie
        case "tv":
            kind = .show
        default:
            return nil
        }

        let title = dto.title ?? dto.name ?? "Unknown"
        let year = dto.releaseDate.flatMap { String($0.prefix(4)) }
            ?? dto.firstAirDate.flatMap { String($0.prefix(4)) }

        return SearchItem(id: dto.id, kind: kind, title: title, posterPath: dto.posterPath, year: year)
    }

    static func trendingItem(_ dto: TMDbTrendingItemDTO, kind: MediaKind) -> SearchItem {
        let title = dto.title ?? dto.name ?? "Unknown"
        let year = dto.releaseDate.flatMap { String($0.prefix(4)) }
            ?? dto.firstAirDate.flatMap { String($0.prefix(4)) }
        let posterPath = dto.posterPath ?? dto.backdropPath ?? dto.profilePath
        return SearchItem(id: dto.id, kind: kind, title: title, posterPath: posterPath, year: year)
    }
}

func parseISODate(_ s: String?) -> Date? {
    guard let s, !s.isEmpty else { return nil }
    return DateFormatters.tmdbYMD.date(from: s)
}
