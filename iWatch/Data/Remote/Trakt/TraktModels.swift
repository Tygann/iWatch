import Foundation

public nonisolated struct TraktIDs: Codable, Sendable, Equatable {
    public let trakt: Int?
    public let slug: String?
    public let tmdb: Int?
    public let imdb: String?
}

public enum TraktMediaType: String, Codable, Sendable {
    case movie, show, season, episode, person
}

public struct TraktDeviceCodeResponse: Codable, Sendable, Equatable {
    public let deviceCode: String
    public let userCode: String
    public let verificationUrl: String
    public let expiresIn: Int
    public let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUrl = "verification_url"
        case expiresIn = "expires_in"
        case interval
    }
}

public struct TokenResponse: Codable, Sendable, Equatable {
    public let accessToken: String
    public let tokenType: String
    public let expiresIn: Int
    public let refreshToken: String
    public let scope: String?
    public let createdAt: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case createdAt = "created_at"
    }

    public nonisolated var issuedAt: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt ?? 0))
    }

    public nonisolated var expiresAt: Date {
        issuedAt.addingTimeInterval(TimeInterval(max(expiresIn, 0)))
    }

    public nonisolated func requiresRefresh(at now: Date = Date()) -> Bool {
        guard expiresIn > 0 else { return true }
        let refreshLeadTime = min(300.0, max(Double(expiresIn) * 0.1, 30.0))
        return now >= expiresAt.addingTimeInterval(-refreshLeadTime)
    }
}

public struct TraktAuthorizationRequest: Sendable, Equatable {
    public let url: URL
    public let state: String
}

struct TraktAccount: Codable, Sendable {
    let ids: TraktAccountIDs

    var syncKey: String {
        if let traktID = ids.trakt {
            return "trakt:\(traktID)"
        }
        return "trakt:uuid:\(ids.uuid.lowercased())"
    }
}

struct TraktAccountIDs: Codable, Sendable {
    let trakt: Int?
    let uuid: String
}

struct TraktSettingsResponse: Codable, Sendable {
    let user: TraktAccount
}


public enum TraktSessionStatus: Sendable, Equatable {
    case disconnected
    case connected
    case reauthorizationRequired(message: String?)
}

public struct TraktWatchlistItemDTO: Codable, Sendable, Equatable {
    public let type: TraktMediaType
    public let listedAt: Date?
    public let movie: TraktMovieDTO?
    public let show: TraktShowDTO?
    public let season: TraktSeasonDTO?
    public let episode: TraktEpisodeDTO?

    enum CodingKeys: String, CodingKey {
        case type
        case movie, show, season, episode
        case listedAt = "listed_at"
    }
}

public struct TraktMovieDTO: Codable, Sendable, Equatable {
    public let title: String?
    public let year: Int?
    public let ids: TraktIDs
}

public struct TraktShowDTO: Codable, Sendable, Equatable {
    public let title: String?
    public let year: Int?
    public let ids: TraktIDs
}

public struct TraktSeasonDTO: Codable, Sendable, Equatable {
    public let number: Int?
    public let ids: TraktIDs
}

public struct TraktEpisodeDTO: Codable, Sendable, Equatable {
    public let season: Int?
    public let number: Int?
    public let title: String?
    public let ids: TraktIDs
}

public struct TraktHistoryItemDTO: Codable, Sendable, Equatable {
    public let id: Int
    public let watchedAt: Date?
    public let action: String?
    public let type: TraktMediaType
    public let movie: TraktMovieDTO?
    public let show: TraktShowDTO?
    public let season: TraktSeasonDTO?
    public let episode: TraktEpisodeDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case watchedAt = "watched_at"
        case action
        case type
        case movie, show, season, episode
    }
}

public struct TraktShowProgressDTO: Codable, Sendable, Equatable {
    public let show: TraktShowDTO
    public let progress: TraktShowProgressSummaryDTO
}

public struct TraktShowProgressSummaryDTO: Codable, Sendable, Equatable {
    public let aired: Int
    public let completed: Int
    public let lastWatchedAt: Date?

    enum CodingKeys: String, CodingKey {
        case aired, completed
        case lastWatchedAt = "last_watched_at"
    }
}

public struct TraktLastActivitiesDTO: Codable, Sendable, Equatable {
    public let all: Date?
    public let movies: TraktActivityGroupDTO?
    public let episodes: TraktActivityGroupDTO?
    public let shows: TraktActivityGroupDTO?
    public let watchlist: TraktActivityTimestampDTO?

    public nonisolated var historyActivityAt: Date? {
        [movies?.watchedAt, episodes?.watchedAt].compactMap { $0 }.max()
    }

    public nonisolated var watchlistActivityAt: Date? {
        [watchlist?.updatedAt, movies?.watchlistedAt, shows?.watchlistedAt].compactMap { $0 }.max()
    }

    public nonisolated var relevantActivityAt: Date? {
        [historyActivityAt, watchlistActivityAt, all].compactMap { $0 }.max()
    }
}

public struct TraktActivityGroupDTO: Codable, Sendable, Equatable {
    public let watchedAt: Date?
    public let watchlistedAt: Date?

    enum CodingKeys: String, CodingKey {
        case watchedAt = "watched_at"
        case watchlistedAt = "watchlisted_at"
    }
}

public struct TraktActivityTimestampDTO: Codable, Sendable, Equatable {
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
    }
}

public nonisolated struct TraktSyncEnvelope: Codable, Sendable, Equatable {
    public var movies: [TraktMoviePayload]?
    public var shows: [TraktShowPayload]?
    public var episodes: [TraktEpisodePayload]?

    public init(movies: [TraktMoviePayload]? = nil,
                shows: [TraktShowPayload]? = nil,
                episodes: [TraktEpisodePayload]? = nil) {
        self.movies = movies
        self.shows = shows
        self.episodes = episodes
    }
}

public nonisolated struct TraktMoviePayload: Codable, Sendable, Equatable {
    public let ids: TraktIDs
    public let watchedAt: Date?

    public init(ids: TraktIDs, watchedAt: Date? = nil) {
        self.ids = ids
        self.watchedAt = watchedAt
    }

    enum CodingKeys: String, CodingKey {
        case ids
        case watchedAt = "watched_at"
    }
}

public nonisolated struct TraktShowPayload: Codable, Sendable, Equatable {
    public let ids: TraktIDs

    public init(ids: TraktIDs) {
        self.ids = ids
    }
}

public nonisolated struct TraktEpisodePayload: Codable, Sendable, Equatable {
    public let ids: TraktIDs
    public let watchedAt: Date?

    public init(ids: TraktIDs, watchedAt: Date? = nil) {
        self.ids = ids
        self.watchedAt = watchedAt
    }

    enum CodingKeys: String, CodingKey {
        case ids
        case watchedAt = "watched_at"
    }
}

public nonisolated struct TraktRemoveHistoryPayload: Codable, Sendable, Equatable {
    public let ids: [Int]
}

public extension JSONDecoder {
    static var trakt: JSONDecoder {
        let d = JSONDecoder()

        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = f.date(from: s) { return date }
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            if let date = f2.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid ISO8601 date: \(s)")
        }

        return d
    }
}

nonisolated struct TraktOAuthErrorResponse: Codable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

enum TraktOAuthError: LocalizedError {
    case oauthFailed(status: Int, error: String, description: String?)
    case unexpected(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case let .oauthFailed(status, error, description):
            return "Trakt OAuth failed (\(status)): \(error)\(description.map { " – \($0)" } ?? "")"
        case let .unexpected(status, body):
            return "Trakt OAuth failed (\(status)): \(body)"
        }
    }
}

struct TraktEmptyResponse: Codable {}

enum TraktAuthError: LocalizedError, Equatable {
    case missingClientID
    case missingClientSecret
    case invalidRedirectURI
    case redirectSchemeNotRegistered(scheme: String)
    case missingAuthorizationCode
    case stateMismatch
    case callbackRejected(error: String, description: String?)
    case sessionExpired(description: String?)

    var requiresReconnect: Bool {
        switch self {
        case .sessionExpired:
            return true
        default:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Trakt client ID is missing from the app configuration."
        case .missingClientSecret:
            return "Trakt client secret is missing from the app configuration."
        case .invalidRedirectURI:
            return "The Trakt redirect URL is invalid."
        case let .redirectSchemeNotRegistered(scheme):
            return "The Trakt redirect URL uses the scheme '\(scheme)', but that scheme is not registered by this app."
        case .missingAuthorizationCode:
            return "Trakt didn’t return an authorization code."
        case .stateMismatch:
            return "The Trakt sign-in response didn’t match this app session. Please try again."
        case let .callbackRejected(error, description):
            return "Trakt authorization failed: \(error)\(description.map { " (\($0))" } ?? "")"
        case let .sessionExpired(description):
            return description ?? "Your Trakt session expired. Reconnect to continue syncing."
        }
    }
}
