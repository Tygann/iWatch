import Foundation

final class TraktService: TraktSyncing {
    private let api: APIClient
    private let clientId: String
    private let clientSecret: String
    private let authStore: TraktAuthStore
    private let base = URL(string: "https://api.trakt.tv")!
    private let authBase = URL(string: "https://auth.trakt.tv")!
    private let encoder: JSONEncoder

    init(apiClient: APIClient, clientId: String, clientSecret: String, authStore: TraktAuthStore = KeychainTraktAuthStore()) {
        self.api = apiClient
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.authStore = authStore
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    func currentToken() async -> TokenResponse? {
        await authStore.currentToken()
    }

    func authenticatedAccount() async throws -> TraktAccount {
        try await refreshTokenIfNeeded()
        let request = try await request(path: "users/settings")
        return try await sendAuthorized(request, decode: TraktSettingsResponse.self).user
    }


    func sessionStatus() async throws -> TraktSessionStatus {
        guard await authStore.currentToken() != nil else {
            return .disconnected
        }

        do {
            try await refreshTokenIfNeeded()
            return await authStore.currentToken() == nil ? .disconnected : .connected
        } catch let error as TraktAuthError where error.requiresReconnect {
            return .reauthorizationRequired(message: error.errorDescription)
        } catch {
            throw error
        }
    }

    func clearAuth() async {
        await authStore.clear()
    }

    func getLastActivities() async throws -> TraktLastActivitiesDTO {
        try await refreshTokenIfNeeded()
        let req = try await request(path: "sync/last_activities")
        return try await sendAuthorized(req, decode: TraktLastActivitiesDTO.self)
    }

    func authorizationRequest(redirectURI: String, state: String) throws -> TraktAuthorizationRequest {
        try validateConfiguration(requiresClientSecret: false)
        guard let redirectURL = URL(string: redirectURI), redirectURL.scheme?.isEmpty == false else {
            throw TraktAuthError.invalidRedirectURI
        }

        var comps = URLComponents(url: authBase.appendingPathComponent("oauth/authorize"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = comps?.url else {
            throw TraktAuthError.invalidRedirectURI
        }
        return TraktAuthorizationRequest(url: url, state: state)
    }

    func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        guard let comps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw TraktAuthError.invalidRedirectURI
        }

        if let oauthError = comps.queryItems?.first(where: { $0.name == "error" })?.value {
            let description = comps.queryItems?.first(where: { $0.name == "error_description" })?.value
            throw TraktAuthError.callbackRejected(error: oauthError, description: description)
        }

        let returnedState = comps.queryItems?.first(where: { $0.name == "state" })?.value
        guard returnedState == expectedState else {
            throw TraktAuthError.stateMismatch
        }

        guard let code = comps.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            throw TraktAuthError.missingAuthorizationCode
        }

        return code
    }

    private func request(path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil, authorized: Bool = true) async throws -> URLRequest {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(clientId, forHTTPHeaderField: "trakt-api-key")
        req.setValue("2", forHTTPHeaderField: "trakt-api-version")
        if authorized, let token = await authStore.currentToken()?.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    func exchangeCodeForToken(code: String, redirectURI: String) async throws -> TokenResponse {
        try validateConfiguration(requiresClientSecret: true)

        let body: [String: Any] = [
            "code": code,
            "client_id": clientId,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]

        let token = try await sendTokenRequest(body: body)
        await authStore.save(token: token)
        return token
    }

    func refreshTokenIfNeeded() async throws {
        guard let current = await authStore.currentToken() else { return }
        guard current.requiresRefresh() else { return }
        try validateConfiguration(requiresClientSecret: true)

        let body: [String: Any] = [
            "refresh_token": current.refreshToken,
            "client_id": clientId,
            "client_secret": clientSecret,
            "grant_type": "refresh_token"
        ]

        do {
            let newToken = try await sendTokenRequest(body: body)
            await authStore.save(token: newToken)
        } catch let error as TraktAuthError where error.requiresReconnect {
            await authStore.clear()
            throw error
        } catch {
            throw error
        }
    }

    func getWatchlist() async throws -> [TraktWatchlistItemDTO] {
        try await refreshTokenIfNeeded()
        return try await paginatedSyncItems { page in
            try await request(
                path: "sync/watchlist",
                query: [
                    URLQueryItem(name: "extended", value: "full"),
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "limit", value: String(Self.syncPageSize))
                ]
            )
        }
    }

    func getHistory(startAt: Date?) async throws -> [TraktHistoryItemDTO] {
        try await refreshTokenIfNeeded()
        var query: [URLQueryItem] = []
        query.append(URLQueryItem(name: "extended", value: "full"))
        if let startAt = startAt {
            let formatter = ISO8601DateFormatter()
            let dateString = formatter.string(from: startAt)
            query.append(URLQueryItem(name: "start_at", value: dateString))
        }
        return try await paginatedSyncItems { page in
            var pageQuery = query
            pageQuery.append(URLQueryItem(name: "page", value: String(page)))
            pageQuery.append(URLQueryItem(name: "limit", value: String(Self.syncPageSize)))
            return try await request(path: "sync/history", query: pageQuery)
        }
    }

    func addToWatchlist(_ items: [MediaID]) async throws {
        try await refreshTokenIfNeeded()

        let movies = items.filter { $0.kind == .movie }.map { TraktMoviePayload(ids: traktIDs(for: $0)) }
        let shows = items.filter { $0.kind == .show }.map { TraktShowPayload(ids: traktIDs(for: $0)) }
        let body = TraktSyncEnvelope(movies: movies.isEmpty ? nil : movies,
                                     shows: shows.isEmpty ? nil : shows,
                                     episodes: nil)
        let req = try await request(path: "sync/watchlist", method: "POST", body: try encoder.encode(body))
        _ = try await sendAuthorized(req, decode: TraktEmptyResponse.self)
    }

    func removeFromWatchlist(_ items: [MediaID]) async throws {
        try await refreshTokenIfNeeded()

        let movies = items.filter { $0.kind == .movie }.map { TraktMoviePayload(ids: traktIDs(for: $0)) }
        let shows = items.filter { $0.kind == .show }.map { TraktShowPayload(ids: traktIDs(for: $0)) }
        let body = TraktSyncEnvelope(movies: movies.isEmpty ? nil : movies,
                                     shows: shows.isEmpty ? nil : shows,
                                     episodes: nil)
        let req = try await request(path: "sync/watchlist/remove", method: "POST", body: try encoder.encode(body))
        _ = try await sendAuthorized(req, decode: TraktEmptyResponse.self)
    }

    func addToHistory(_ payloads: [SyncOperationPayload]) async throws {
        try await refreshTokenIfNeeded()

        let movies = payloads
            .filter { $0.mediaKind == .movie }
            .compactMap { payload -> TraktMoviePayload? in
                guard let tmdbID = payload.tmdbID, let watchedAt = payload.watchedAt else { return nil }
                return TraktMoviePayload(ids: TraktIDs(trakt: payload.traktID, slug: nil, tmdb: tmdbID, imdb: nil), watchedAt: watchedAt)
            }

        let episodes = payloads
            .filter { $0.mediaKind == .episode }
            .compactMap { payload -> TraktEpisodePayload? in
                guard let tmdbID = payload.tmdbID, let watchedAt = payload.watchedAt else { return nil }
                return TraktEpisodePayload(ids: TraktIDs(trakt: payload.traktID, slug: nil, tmdb: tmdbID, imdb: nil), watchedAt: watchedAt)
            }

        let body = TraktSyncEnvelope(movies: movies.isEmpty ? nil : movies,
                                     shows: nil,
                                     episodes: episodes.isEmpty ? nil : episodes)
        let req = try await request(path: "sync/history", method: "POST", body: try encoder.encode(body))
        _ = try await sendAuthorized(req, decode: TraktEmptyResponse.self)
    }

    func removeFromHistory(historyIDs: [Int]) async throws {
        try await refreshTokenIfNeeded()

        let body = TraktRemoveHistoryPayload(ids: historyIDs)
        let req = try await request(path: "sync/history/remove", method: "POST", body: try encoder.encode(body))
        _ = try await sendAuthorized(req, decode: TraktEmptyResponse.self)
    }

    private func traktIDs(for mediaID: MediaID) -> TraktIDs {
        TraktIDs(trakt: mediaID.traktID, slug: nil, tmdb: mediaID.tmdbID, imdb: nil)
    }

    private static let syncPageSize = 100

    private func paginatedSyncItems<Item: Decodable>(
        requestForPage: (Int) async throws -> URLRequest
    ) async throws -> [Item] {
        var page = 1
        var items: [Item] = []

        while true {
            let request = try await requestForPage(page)
            let pageItems = try await sendAuthorized(
                request,
                decode: [Item].self
            )
            items.append(contentsOf: pageItems)

            guard pageItems.count == Self.syncPageSize else { return items }
            page += 1
        }
    }

    private func validateConfiguration(requiresClientSecret: Bool) throws {
        guard clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw TraktAuthError.missingClientID
        }
        if requiresClientSecret {
            guard clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw TraktAuthError.missingClientSecret
            }
        }
    }

    private func sendTokenRequest(body: [String: Any]) async throws -> TokenResponse {
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var req = URLRequest(url: authBase.appendingPathComponent("oauth/token"))
        req.httpMethod = "POST"
        req.httpBody = bodyData
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let token = try await api.send(req, decode: TokenResponse.self, decoder: .trakt)
            return normalized(token: token)
        } catch let error as AppError {
            throw mapOAuthError(error)
        } catch {
            throw error
        }
    }

    private func sendAuthorized<T: Decodable>(_ request: URLRequest, decode: T.Type) async throws -> T {
        do {
            return try await api.send(request, decode: decode, decoder: .trakt)
        } catch let error as AppError {
            if case let .httpStatus(code, _) = error, code == 401 {
                await authStore.clear()
                throw TraktAuthError.sessionExpired(description: nil)
            }
            throw error
        } catch {
            throw error
        }
    }

    private func normalized(token: TokenResponse) -> TokenResponse {
        let createdAt = token.createdAt ?? Int(Date().timeIntervalSince1970)
        return TokenResponse(
            accessToken: token.accessToken,
            tokenType: token.tokenType,
            expiresIn: token.expiresIn,
            refreshToken: token.refreshToken,
            scope: token.scope,
            createdAt: createdAt
        )
    }

    private func mapOAuthError(_ error: AppError) -> Error {
        guard case let .httpStatus(code, message) = error else {
            return error
        }

        let body = message ?? ""
        if let data = body.data(using: .utf8),
           let oauth = try? JSONDecoder().decode(TraktOAuthErrorResponse.self, from: data) {
            if oauth.error == "invalid_grant" || code == 401 {
                return TraktAuthError.sessionExpired(description: oauth.errorDescription)
            }
            return TraktOAuthError.oauthFailed(status: code, error: oauth.error, description: oauth.errorDescription)
        }

        if code == 401 {
            return TraktAuthError.sessionExpired(description: nil)
        }

        return TraktOAuthError.unexpected(status: code, body: body)
    }
}

typealias TraktClient = TraktService
