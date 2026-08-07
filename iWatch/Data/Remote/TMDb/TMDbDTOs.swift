import Foundation

// Keep DTOs minimal to start; expand as needed.

// MARK: - Movie
struct TMDbMovieDetailsDTO: Decodable {
    let id: Int
    let title: String
    let overview: String?
    let tagline: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let voteCount: Int?
    let genres: [TMDbGenreDTO]
    let releaseDate: String?
    let runtime: Int?
}

// MARK: - Show
struct TMDbShowDetailsDTO: Decodable {
    let id: Int
    let name: String
    let overview: String?
    let tagline: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let voteCount: Int?
    let genres: [TMDbGenreDTO]
    let firstAirDate: String?
    let lastAirDate: String?
    let numberOfEpisodes: Int?
    let seasons: [TMDbSeasonSummaryDTO]   // ummaries, not full seasons
    let status: String?                // "Returning Series", "Ended", "Canceled", etc.
    let inProduction: Bool?            // maps from "in_production"
    let nextEpisodeToAir: TMDbNextEpisodeStub?  // maps from "next_episode_to_air"
}

// Minimal stub just for the next air date
struct TMDbNextEpisodeStub: Decodable {
    let airDate: String?   // "yyyy-MM-dd"
}

// MARK: - Season
// Summary used inside /tv/{id}
struct TMDbSeasonSummaryDTO: Decodable {
    let id: Int
    let seasonNumber: Int
    let name: String
    let episodeCount: Int?
    let posterPath: String?
}

// Full season payload from /tv/{id}/season/{n}
struct TMDbSeasonDetailsDTO: Decodable {
    let id: Int
    let seasonNumber: Int
    let name: String
    let episodes: [TMDbEpisodeDTO]        // only here
    let posterPath: String?
}

// MARK: - Episode
//struct TMDbEpisodeDTO: Decodable {
//    let id: Int
//    let episodeNumber: Int
//    let name: String
//    let airDate: Date?
//    let stillPath: String?
//    let overview: String?
//}

// Full episode payload from
// /tv/{showId}/season/{seasonNumber}/episode/{episodeNumber}?append_to_response=credits,images,videos,external_ids
struct TMDbEpisodeDTO: Decodable {
    struct Crew: Decodable {
        let id: Int
        let name: String
        let job: String?
        let department: String?
        let profilePath: String?
    }
    struct Guest: Decodable {
        let id: Int
        let name: String
        let character: String?
        let profilePath: String?
    }
    struct Cast: Decodable {
        let id: Int
        let name: String
        let character: String?
        let profilePath: String?
        let order: Int?
    }
    struct Credits: Decodable {
        let cast: [Cast]?
        let guestStars: [Guest]?
        let crew: [Crew]?
    }
    struct Images: Decodable {
        struct Still: Decodable { let filePath: String? }
        let stills: [Still]?
    }
    struct Videos: Decodable {
        struct Video: Decodable { let id: String; let key: String; let name: String; let site: String; let type: String }
        let results: [Video]
    }
    struct ExternalIDs: Decodable {
        let imdbId: String?
        let tvdbId: Int?
        let facebookId: String?
        let instagramId: String?
        let twitterId: String?
    }

    // Core
    let id: Int
    let name: String
    let overview: String?
    let stillPath: String?
    let airDate: Date?
    let runtime: Int?
    let voteAverage: Double?
    let voteCount: Int?
    let productionCode: String?
    let episodeNumber: Int
    let seasonNumber: Int

    // Appended blocks
    let credits: Credits?
    let images: Images?
    let videos: Videos?
    let externalIds: ExternalIDs?
}

// MARK: - Other
struct TMDbPersonDetailsDTO: Decodable {
    let id: Int
    let name: String
    let biography: String?
    let profilePath: String?
    let combinedCredits: TMDbCombinedCreditsDTO?
}

struct TMDbGenreDTO: Decodable {
    let id: Int
    let name: String
}

struct TMDbCombinedCreditsDTO: Decodable {
    let cast: [TMDbCreditDTO]
}

struct TMDbCreditDTO: Decodable {
    let mediaType: String? // "movie" | "tv"
    let id: Int?
    let title: String?
    let name: String?
    let posterPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let popularity: Double?
}

struct TMDbMultiSearchPageDTO: Decodable {
    let results: [TMDbMultiSearchItemDTO]
}

struct TMDbMultiSearchItemDTO: Decodable {
    let mediaType: String
    let id: Int
    let title: String?
    let name: String?
    let posterPath: String?
    let releaseDate: String?
    let firstAirDate: String?
}

struct TMDbTrendingPageDTO: Decodable {
    let results: [TMDbTrendingItemDTO]
}

struct TMDbTrendingItemDTO: Decodable {
    let mediaType: String?
    let id: Int
    let title: String?
    let name: String?
    let posterPath: String?
    let backdropPath: String?
    let profilePath: String?
    let releaseDate: String?
    let firstAirDate: String?
}

struct TMDbWatchProviderPageDTO: Decodable {
    let results: [TMDbWatchProviderDTO]
}

struct TMDbWatchProviderDTO: Decodable {
    let providerId: Int
    let providerName: String
    let logoPath: String?
    let displayPriority: Int?
}

// MARK: - Movie / Show supplementary details
struct TMDbMediaSupplementaryDTO: Decodable {
    struct Credit: Decodable {
        let id: Int
        let name: String
        let character: String?
        let job: String?
        let profilePath: String?
        let order: Int?
    }

    struct Credits: Decodable {
        let cast: [Credit]?
        let crew: [Credit]?
    }

    struct Creator: Decodable {
        let id: Int
        let name: String
        let profilePath: String?
    }

    struct Videos: Decodable {
        struct Video: Decodable {
            let id: String
            let name: String
            let key: String
            let site: String
            let type: String
            let official: Bool?
        }

        let results: [Video]
    }

    struct WatchProviders: Decodable {
        struct Provider: Decodable {
            let providerId: Int
            let providerName: String
            let logoPath: String?
            let displayPriority: Int?
        }

        struct Availability: Decodable {
            let link: URL?
            let flatrate: [Provider]?
            let free: [Provider]?
            let ads: [Provider]?
            let rent: [Provider]?
            let buy: [Provider]?
        }

        let results: [String: Availability]
    }

    struct MovieReleaseDates: Decodable {
        struct Country: Decodable {
            struct Release: Decodable {
                let certification: String
                let type: Int
            }

            let iso31661: String
            let releaseDates: [Release]
        }

        let results: [Country]
    }

    struct TVContentRatings: Decodable {
        struct Rating: Decodable {
            let iso31661: String
            let rating: String
        }

        let results: [Rating]
    }

    let credits: Credits?
    let createdBy: [Creator]?
    let videos: Videos?
    let watchProviders: WatchProviders?
    let releaseDates: MovieReleaseDates?
    let contentRatings: TVContentRatings?

    enum CodingKeys: String, CodingKey {
        case credits
        case createdBy
        case videos
        case watchProviders = "watch/providers"
        case releaseDates
        case contentRatings
    }
}
