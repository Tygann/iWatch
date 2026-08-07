import Foundation

enum TMDbMappers {
    static func supplementary(
        _ dto: TMDbMediaSupplementaryDTO,
        kind: MediaKind,
        regionCode: String
    ) -> MediaSupplementaryDetails {
        let cast = (dto.credits?.cast ?? [])
            .sorted { ($0.order ?? .max) < ($1.order ?? .max) }
            .prefix(15)
            .map {
                MediaSupplementaryDetails.Credit(
                    id: $0.id,
                    name: $0.name,
                    subtitle: $0.character,
                    profilePath: $0.profilePath,
                    order: $0.order
                )
            }

        let preferredJobs = kind == .movie
            ? ["Director", "Screenplay", "Writer"]
            : ["Executive Producer", "Director", "Writer"]
        let crew = preferredJobs.flatMap { job in
            (dto.credits?.crew ?? [])
                .filter { $0.job?.caseInsensitiveCompare(job) == .orderedSame }
                .prefix(3)
                .map {
                    MediaSupplementaryDetails.Credit(
                        id: $0.id,
                        name: $0.name,
                        subtitle: $0.job,
                        profilePath: $0.profilePath,
                        order: nil
                    )
                }
        }
        let creators = (dto.createdBy ?? []).map {
            MediaSupplementaryDetails.Credit(
                id: $0.id,
                name: $0.name,
                subtitle: "Creator",
                profilePath: $0.profilePath,
                order: nil
            )
        }

        var seenCreditIDs = Set<Int>()
        let credits = (cast + creators + crew).filter { seenCreditIDs.insert($0.id).inserted }

        let region = regionCode.uppercased()
        let availabilityDTO = dto.watchProviders?.results[region]
        func providers(_ values: [TMDbMediaSupplementaryDTO.WatchProviders.Provider]?) -> [MediaSupplementaryDetails.WatchProvider] {
            var seenProviderIDs = Set<Int>()
            return (values ?? [])
                .sorted { ($0.displayPriority ?? .max) < ($1.displayPriority ?? .max) }
                .filter { seenProviderIDs.insert($0.providerId).inserted }
                .map { .init(id: $0.providerId, name: $0.providerName, logoPath: $0.logoPath) }
        }
        let streamDTO = (availabilityDTO?.flatrate ?? []) + (availabilityDTO?.free ?? []) + (availabilityDTO?.ads ?? [])
        let availability = availabilityDTO.map {
            MediaSupplementaryDetails.WatchAvailability(
                link: $0.link,
                stream: providers(streamDTO),
                rent: providers($0.rent),
                buy: providers($0.buy)
            )
        }

        let certification: String? = {
            switch kind {
            case .movie:
                let releases = dto.releaseDates?.results.first { $0.iso31661.caseInsensitiveCompare(region) == .orderedSame }?.releaseDates
                    ?? dto.releaseDates?.results.first { $0.iso31661 == "US" }?.releaseDates
                    ?? []
                return releases
                    .filter { !$0.certification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .sorted { releasePriority($0.type) < releasePriority($1.type) }
                    .first?.certification
            case .show:
                return dto.contentRatings?.results.first { $0.iso31661.caseInsensitiveCompare(region) == .orderedSame }?.rating
                    ?? dto.contentRatings?.results.first { $0.iso31661 == "US" }?.rating
            default:
                return nil
            }
        }()

        let videos = (dto.videos?.results ?? []).map {
            MediaSupplementaryDetails.Video(
                id: $0.id,
                name: $0.name,
                key: $0.key,
                site: $0.site,
                type: $0.type,
                official: $0.official ?? false
            )
        }

        return .init(
            credits: credits,
            watchAvailability: availability,
            certification: certification?.isEmpty == false ? certification : nil,
            videos: videos
        )
    }

    private static func releasePriority(_ type: Int) -> Int {
        switch type {
        case 3: 0 // Theatrical
        case 4: 1 // Digital
        case 5: 2 // Physical
        case 6: 3 // TV
        default: 4
        }
    }

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
        let rawCredits = (d.combinedCredits?.cast ?? []) + (d.combinedCredits?.crew ?? [])
        var creditsByMedia: [MediaID: [TMDbCreditDTO]] = [:]
        for credit in rawCredits {
            guard let id = credit.id else { continue }
            let kind: MediaKind
            switch credit.mediaType {
            case "movie": kind = .movie
            case "tv": kind = .show
            default: continue
            }
            creditsByMedia[MediaID(kind: kind, id: id), default: []].append(credit)
        }

        let credits = creditsByMedia.compactMap { mediaID, entries -> PersonDetails.Credit? in
            let rankedEntries = entries.sorted {
                ($0.popularity ?? 0) > ($1.popularity ?? 0)
            }

            let title = rankedEntries.compactMap { $0.title ?? $0.name }.first
            guard let title, !title.isEmpty else { return nil }
            let year = rankedEntries.compactMap { entry in
                entry.releaseDate.flatMap { String($0.prefix(4)) }
                    ?? entry.firstAirDate.flatMap { String($0.prefix(4)) }
            }.first
            let posterPath = rankedEntries.compactMap(\.posterPath).first

            var seenRoles = Set<String>()
            let roles = entries.compactMap { entry -> String? in
                let role = entry.character ?? entry.job
                guard let role = role?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !role.isEmpty,
                      seenRoles.insert(role).inserted else { return nil }
                return role
            }

            var seenDepartments = Set<String>()
            let departments = entries.compactMap { entry -> String? in
                let department = entry.department ?? (entry.character == nil ? nil : "Acting")
                guard let department = department?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !department.isEmpty,
                      seenDepartments.insert(department).inserted else { return nil }
                return department
            }

            return PersonDetails.Credit(
                media: SearchItem(
                    id: mediaID.id,
                    kind: mediaID.kind,
                    title: title,
                    posterPath: posterPath,
                    year: year
                ),
                role: roles.isEmpty ? nil : roles.joined(separator: " • "),
                departments: departments,
                popularity: entries.map { $0.popularity ?? 0 }.max() ?? 0
            )
        }

        let filmography = credits.sorted {
            if $0.media.year != $1.media.year {
                return ($0.media.year ?? "") > ($1.media.year ?? "")
            }
            if $0.popularity != $1.popularity {
                return $0.popularity > $1.popularity
            }
            return $0.media.title.localizedCaseInsensitiveCompare($1.media.title) == .orderedAscending
        }
        let knownFor = credits.sorted {
            if $0.popularity != $1.popularity {
                return $0.popularity > $1.popularity
            }
            return $0.media.title.localizedCaseInsensitiveCompare($1.media.title) == .orderedAscending
        }
        let external = d.externalIds

        return PersonDetails(
            id: d.id,
            name: d.name,
            biography: d.biography,
            profilePath: d.profilePath,
            knownForDepartment: d.knownForDepartment,
            birthday: d.birthday.flatMap(DateFormatters.tmdbYMD.date(from:)),
            deathday: d.deathday.flatMap(DateFormatters.tmdbYMD.date(from:)),
            placeOfBirth: d.placeOfBirth,
            homepage: d.homepage.flatMap(URL.init(string:)),
            externalIDs: PersonDetails.ExternalIDs(
                imdb: external?.imdbId,
                facebook: external?.facebookId,
                instagram: external?.instagramId,
                tiktok: external?.tiktokId,
                twitter: external?.twitterId,
                youtube: external?.youtubeId
            ),
            knownFor: Array(knownFor.prefix(12)),
            credits: filmography
        )
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

    static func mixedTrendingItem(_ dto: TMDbTrendingItemDTO) -> SearchItem? {
        let kind: MediaKind
        switch dto.mediaType {
        case "movie": kind = .movie
        case "tv": kind = .show
        default: return nil
        }
        return trendingItem(dto, kind: kind)
    }
}

func parseISODate(_ s: String?) -> Date? {
    guard let s, !s.isEmpty else { return nil }
    return DateFormatters.tmdbYMD.date(from: s)
}
