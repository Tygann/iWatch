import Foundation
import CryptoKit

// MARK: - Trakt Service

final class TraktService: TraktSyncing, EpisodeAirtimeProviding {
    private let api: APIClient
    private let clientId: String
    private let authStore: TraktAuthStore
    private let base = URL(string: "https://api.trakt.tv")!
    private let authBase = URL(string: "https://auth.trakt.tv")!
    private let encoder: JSONEncoder
    private let refreshCoordinator = TokenRefreshCoordinator()

    init(apiClient: APIClient, clientId: String, clientSecret _: String, authStore: TraktAuthStore = KeychainTraktAuthStore()) {
        self.api = apiClient
        self.clientId = clientId
        self.authStore = authStore
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: Session

    func currentToken() async -> TokenResponse? {
        await authStore.currentToken()
    }

    func authenticatedAccount() async throws -> TraktAccount {
        try await verifiedSession().account
    }

    func authorizeSync(accountKey: String?) async throws -> TraktSyncSession? {
        guard let accountKey else { throw CancellationError() }
        let verified = try await verifiedSession()
        guard verified.account.syncKey == accountKey else { throw CancellationError() }
        return verified.session
    }

    func validateSyncAuthorization() async throws {
        try Task.checkCancellation()
        if let session = TraktSyncSession.current,
           !(await refreshCoordinator.isCurrent(session.generation)) {
            throw CancellationError()
        }
    }

    private func verifiedSession() async throws -> (account: TraktAccount, session: TraktSyncSession) {
        let generation = await refreshCoordinator.currentGeneration()
        try await refreshTokenIfNeeded()
        guard let token = await authStore.currentToken(),
              await refreshCoordinator.isCurrent(generation) else { throw CancellationError() }
        var request = try await request(path: "users/settings", authorized: false)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer " + token.accessToken, forHTTPHeaderField: "Authorization")
        let account = try await sendAuthorized(request, decode: TraktSettingsResponse.self).user
        guard await refreshCoordinator.isCurrent(generation) else { throw CancellationError() }
        return (account, TraktSyncSession(accountKey: account.syncKey, generation: generation, accessToken: token.accessToken))
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
        _ = await refreshCoordinator.invalidate()
        await refreshCoordinator.clear(authStore)
    }

    // MARK: Public Episode Metadata

    func episodeAirtime(traktID: Int) async throws -> EpisodeAirtime {
        let req = try await request(
            path: "episodes/\(traktID)",
            query: [URLQueryItem(name: "extended", value: "full")],
            authorized: false
        )
        let episode = try await api.send(req, decode: TraktEpisodeDTO.self, decoder: .trakt)
        return airtime(from: episode)
    }

    func seasonAirtimes(showTraktID: Int, seasonNumber: Int) async throws -> [EpisodeAirtime] {
        let req = try await request(
            path: "shows/\(showTraktID)/seasons/\(seasonNumber)",
            query: [URLQueryItem(name: "extended", value: "full")],
            authorized: false
        )
        let episodes = try await api.send(req, decode: [TraktEpisodeDTO].self, decoder: .trakt)
        return episodes.compactMap { episode in
            guard episode.season != nil, episode.number != nil else { return nil }
            return airtime(from: episode)
        }
    }

    private func airtime(from episode: TraktEpisodeDTO) -> EpisodeAirtime {
        EpisodeAirtime(
            traktID: episode.ids.trakt,
            tmdbID: episode.ids.tmdb,
            seasonNumber: episode.season ?? 0,
            episodeNumber: episode.number ?? 0,
            airedAt: episode.firstAired
        )
    }

    func getLastActivities() async throws -> TraktLastActivitiesDTO {
        try await refreshTokenIfNeeded()
        let req = try await request(path: "sync/last_activities")
        return try await sendAuthorized(req, decode: TraktLastActivitiesDTO.self)
    }

    // MARK: OAuth

    func authorizationRequest(redirectURI: String, state: String) throws -> TraktAuthorizationRequest {
        try validateConfiguration()
        guard let redirectURL = URL(string: redirectURI), redirectURL.scheme?.isEmpty == false else {
            throw TraktAuthError.invalidRedirectURI
        }

        let verifier = OAuthStateGenerator.make(byteCount: 64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var comps = URLComponents(url: authBase.appendingPathComponent("oauth/authorize"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = comps?.url else {
            throw TraktAuthError.invalidRedirectURI
        }
        return TraktAuthorizationRequest(url: url, state: state, codeVerifier: verifier)
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
        if authorized {
            let token: String?
            if let session = TraktSyncSession.current {
                try await validateSyncAuthorization()
                token = session.accessToken
            } else {
                token = await authStore.currentToken()?.accessToken
            }
            if let token {
                req.cachePolicy = .reloadIgnoringLocalCacheData
                req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            }
        }
        return req
    }

    func exchangeCodeForToken(code: String, redirectURI: String, codeVerifier: String) async throws -> TokenResponse {
        let generation = await refreshCoordinator.invalidate()
        try validateConfiguration()

        let body: [String: Any] = [
            "code": code,
            "client_id": clientId,
            "code_verifier": codeVerifier,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]

        let token = try await sendTokenRequest(body: body)
        guard await refreshCoordinator.isCurrent(generation) else { throw CancellationError() }
        try await refreshCoordinator.save(token, generation: generation, in: authStore)
        return token
    }

    func refreshTokenIfNeeded() async throws {
        if TraktSyncSession.current != nil {
            try await validateSyncAuthorization()
            return
        }
        try await refreshCoordinator.run { generation in
            try await self.performTokenRefresh(generation: generation)
        }
    }

    private func performTokenRefresh(generation: UUID) async throws {
        guard let current = await authStore.currentToken() else { return }
        guard current.requiresRefresh() else { return }
        try validateConfiguration()

        let body: [String: Any] = [
            "refresh_token": current.refreshToken,
            "client_id": clientId,
            "grant_type": "refresh_token"
        ]

        do {
            let newToken = try await sendTokenRequest(body: body)
            try Task.checkCancellation()
            guard await refreshCoordinator.isCurrent(generation) else { throw CancellationError() }
            try await refreshCoordinator.save(newToken, generation: generation, in: authStore)
        } catch let error as TraktAuthError where error.requiresReconnect {
            guard await refreshCoordinator.isCurrent(generation) else { throw CancellationError() }
            await refreshCoordinator.clear(authStore)
            throw error
        } catch {
            throw error
        }
    }

    // MARK: Library Sync

    func getWatchlist() async throws -> [TraktWatchlistItemDTO] {
        try await getWatchlist(progress: nil)
    }

    func getWatchlist(progress: (@Sendable (Int) async -> Void)?) async throws -> [TraktWatchlistItemDTO] {
        try await refreshTokenIfNeeded()
        return try await paginatedSyncItems(progress: progress) { page in
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
        try await getHistory(startAt: startAt, progress: nil)
    }

    func getHistory(startAt: Date?, endAt: Date?) async throws -> [TraktHistoryItemDTO] {
        try await history(startAt: startAt, endAt: endAt, progress: nil)
    }

    func getHistory(startAt: Date?, progress: (@Sendable (Int) async -> Void)?) async throws -> [TraktHistoryItemDTO] {
        try await history(startAt: startAt, endAt: nil, progress: progress)
    }

    private func history(startAt: Date?, endAt: Date?, progress: (@Sendable (Int) async -> Void)?) async throws -> [TraktHistoryItemDTO] {
        try await refreshTokenIfNeeded()
        var query: [URLQueryItem] = []
        query.append(URLQueryItem(name: "extended", value: "full"))
        if let startAt = startAt {
            let formatter = ISO8601DateFormatter()
            let dateString = formatter.string(from: startAt)
            query.append(URLQueryItem(name: "start_at", value: dateString))
        }
        if let endAt {
            query.append(URLQueryItem(name: "end_at", value: ISO8601DateFormatter().string(from: endAt)))
        }
        return try await paginatedSyncItems(progress: progress) { page in
            var pageQuery = query
            pageQuery.append(URLQueryItem(name: "page", value: String(page)))
            pageQuery.append(URLQueryItem(name: "limit", value: String(Self.syncPageSize)))
            var request = try await request(path: "sync/history", query: pageQuery)
            if endAt != nil { request.cachePolicy = .reloadIgnoringLocalCacheData }
            return request
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

    func addToHistory(_ payload: SyncOperationPayload) async throws {
        guard let kind = payload.mediaKind, let tmdbID = payload.tmdbID, let watchedAt = payload.watchedAt,
              kind == .movie || kind == .episode else {
            throw TraktHistoryUploadError.invalidPlay
        }
        try await refreshTokenIfNeeded()

        let ids = TraktIDs(trakt: payload.traktID, slug: nil, tmdb: tmdbID, imdb: nil)
        let body = TraktSyncEnvelope(
            movies: kind == .movie ? [TraktMoviePayload(ids: ids, watchedAt: watchedAt)] : nil,
            shows: nil,
            episodes: kind == .episode ? [TraktEpisodePayload(ids: ids, watchedAt: watchedAt)] : nil
        )
        let request = try await request(path: "sync/history", method: "POST", body: try encoder.encode(body))
        let result = try await sendAuthorized(request, decode: TraktHistoryUploadResponse.self)
        let rejected = kind == .movie ? result.notFound.movies : result.notFound.episodes
        // A single-item request makes the item-level rejection attributable to this play.
        if result.added.movies == 0, result.added.episodes == 0, rejected?.count == 1,
           let rejectedIDs = rejected?.first?.ids,
           rejectedIDs.tmdb == tmdbID || (ids.trakt != nil && rejectedIDs.trakt == ids.trakt) {
            throw TraktHistoryUploadError.itemNotFound
        }
    }

    func removeFromHistory(historyIDs: [Int]) async throws {
        try await refreshTokenIfNeeded()

        let body = TraktRemoveHistoryPayload(ids: historyIDs)
        let req = try await request(path: "sync/history/remove", method: "POST", body: try encoder.encode(body))
        _ = try await sendAuthorized(req, decode: TraktEmptyResponse.self)
    }

    // MARK: Request Helpers

    private func traktIDs(for mediaID: MediaID) -> TraktIDs {
        TraktIDs(trakt: mediaID.traktID, slug: nil, tmdb: mediaID.tmdbID, imdb: nil)
    }

    private static let syncPageSize = 100

    private func paginatedSyncItems<Item: Decodable>(
        progress: (@Sendable (Int) async -> Void)?,
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
            await progress?(items.count)

            guard pageItems.count == Self.syncPageSize else { return items }
            page += 1
        }
    }

    private func validateConfiguration() throws {
        guard clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw TraktAuthError.missingClientID
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
            try await validateSyncAuthorization()
            let result = try await api.send(request, decode: decode, decoder: .trakt)
            try await validateSyncAuthorization()
            return result
        } catch let error as AppError {
            if case let .httpStatus(code, _) = error, code == 401 {
                let cleared = await refreshCoordinator.clear(authStore, matching: request.value(forHTTPHeaderField: "Authorization"))
                guard cleared else { throw CancellationError() }
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

private actor TokenRefreshCoordinator {
    private var generation = UUID()
    private var task: Task<Void, Error>?
    private var lastWrite: Task<Void, Never>?

    func currentGeneration() -> UUID { generation }

    func isCurrent(_ value: UUID) -> Bool { value == generation }

    func invalidate() -> UUID {
        generation = UUID()
        task?.cancel()
        task = nil
        return generation
    }

    func save(_ token: TokenResponse, generation expected: UUID, in store: any TraktAuthStore) async throws {
        guard expected == generation else { throw CancellationError() }
        let previous = lastWrite
        let write = Task { await previous?.value; await store.save(token: token) }
        lastWrite = write
        await write.value
    }

    @discardableResult
    func clear(_ store: any TraktAuthStore, matching authorization: String? = nil) async -> Bool {
        let previous = lastWrite
        let result = Task { () -> Bool in
            await previous?.value
            if let authorization {
                guard let token = await store.currentToken(), authorization == "Bearer " + token.accessToken else { return false }
            }
            await store.clear()
            return true
        }
        lastWrite = Task { _ = await result.value }
        return await result.value
    }

    func run(_ refresh: @escaping @Sendable (UUID) async throws -> Void) async throws {
        if let task { return try await task.value }
        let current = generation
        let work = Task { try await refresh(current) }
        task = work
        defer { if generation == current { task = nil } }
        try await work.value
    }
}
