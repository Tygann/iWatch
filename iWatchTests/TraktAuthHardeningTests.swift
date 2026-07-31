import Foundation
import Testing
@testable import iWatch

@MainActor
@Suite(.serialized)
struct TraktAuthHardeningTests {
    @Test
    func authorizationRequestIncludesStateAndRedirectURI() throws {
        let service = makeTraktService()

        let request = try service.authorizationRequest(
            redirectURI: "com.tyler.iWatch://oauth/callback",
            state: "state-123"
        )

        let components = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        #expect(request.state == "state-123")
        #expect(components.host == "auth.trakt.tv")
        #expect(components.path == "/oauth/authorize")
        #expect(queryItems["response_type"] == "code")
        #expect(queryItems["client_id"] == "client-id")
        #expect(queryItems["redirect_uri"] == "com.tyler.iWatch://oauth/callback")
        #expect(queryItems["state"] == "state-123")
    }

    @Test
    func authorizationCodeRejectsStateMismatch() throws {
        let service = makeTraktService()
        let callbackURL = try #require(URL(string: "com.tyler.iWatch://oauth/callback?code=abc123&state=unexpected"))

        #expect(throws: TraktAuthError.stateMismatch) {
            try service.authorizationCode(from: callbackURL, expectedState: "expected")
        }
    }

    @Test
    func sessionStatusClearsTokenWhenRefreshIsRejected() async throws {
        let authStore = InMemoryTraktAuthStore()
        await authStore.save(token: TokenResponse(
            accessToken: "expired-access",
            tokenType: "bearer",
            expiresIn: 3600,
            refreshToken: "stale-refresh",
            scope: "public",
            createdAt: Int(Date().addingTimeInterval(-7200).timeIntervalSince1970)
        ))

        MockTraktURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 401,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = #"{"error":"invalid_grant","error_description":"Refresh token is no longer valid."}"#
            return (response, Data(body.utf8))
        }
        defer { MockTraktURLProtocol.handler = nil }

        let service = makeTraktService(authStore: authStore)
        let status = try await service.sessionStatus()

        #expect(status == .reauthorizationRequired(message: "Refresh token is no longer valid."))
        #expect(await authStore.currentToken() == nil)
    }

    @Test
    func exchangeCodeNormalizesAndStoresToken() async throws {
        let authStore = InMemoryTraktAuthStore()

        MockTraktURLProtocol.handler = { request in
            let url = try #require(request.url)
            #expect(url.host == "auth.trakt.tv")
            #expect(url.path == "/oauth/token")
            #expect(request.httpMethod == "POST")

            let bodyData = try #require(request.bodyData)
            let object = try JSONSerialization.jsonObject(with: bodyData) as? [String: String]
            #expect(object?["code"] == "auth-code")
            #expect(object?["grant_type"] == "authorization_code")
            #expect(object?["client_id"] == "client-id")
            #expect(object?["client_secret"] == "client-secret")
            #expect(object?["redirect_uri"] == "com.tyler.iWatch://oauth/callback")

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = #"{"access_token":"new-access","token_type":"bearer","expires_in":3600,"refresh_token":"new-refresh","scope":"public"}"#
            return (response, Data(body.utf8))
        }
        defer { MockTraktURLProtocol.handler = nil }

        let service = makeTraktService(authStore: authStore)
        let token = try await service.exchangeCodeForToken(
            code: "auth-code",
            redirectURI: "com.tyler.iWatch://oauth/callback"
        )

        let stored = await authStore.currentToken()
        #expect(token.accessToken == "new-access")
        #expect(token.createdAt != nil)
        #expect(stored?.accessToken == "new-access")
        #expect(stored?.createdAt != nil)
    }

    @Test
    func authenticatedAccountUsesUUIDWhenLegacyTraktIDIsNull() async throws {
        let authStore = InMemoryTraktAuthStore()
        await authStore.save(token: validToken())

        MockTraktURLProtocol.handler = { request in
            let url = try #require(request.url)
            #expect(url.path == "/users/settings")

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = #"{"user":{"ids":{"trakt":null,"uuid":"A12B34CD-5678"}}}"#
            return (response, Data(body.utf8))
        }
        defer { MockTraktURLProtocol.handler = nil }

        let account = try await makeTraktService(authStore: authStore).authenticatedAccount()

        #expect(account.syncKey == "trakt:uuid:a12b34cd-5678")
    }

    @Test
    func authenticatedAccountPreservesLegacyTraktIDWhenAvailable() async throws {
        let authStore = InMemoryTraktAuthStore()
        await authStore.save(token: validToken())

        MockTraktURLProtocol.handler = { request in
            let url = try #require(request.url)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = #"{"user":{"ids":{"trakt":42,"uuid":"A12B34CD-5678"}}}"#
            return (response, Data(body.utf8))
        }
        defer { MockTraktURLProtocol.handler = nil }

        let account = try await makeTraktService(authStore: authStore).authenticatedAccount()

        #expect(account.syncKey == "trakt:42")
    }
}

private func validToken() -> TokenResponse {
    TokenResponse(
        accessToken: "valid-access",
        tokenType: "bearer",
        expiresIn: 3600,
        refreshToken: "valid-refresh",
        scope: "public",
        createdAt: Int(Date().timeIntervalSince1970)
    )
}

private func makeTraktService(authStore: TraktAuthStore = InMemoryTraktAuthStore()) -> TraktService {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockTraktURLProtocol.self]
    let session = URLSession(configuration: config)
    let api = APIClient(session: session)
    return TraktService(
        apiClient: api,
        clientId: "client-id",
        clientSecret: "client-secret",
        authStore: authStore
    )
}

private final class MockTraktURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    var bodyData: Data? {
        if let httpBody {
            return httpBody
        }

        guard let stream = httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        let bufferSize = 1024
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead < 0 {
                return nil
            }
            if bytesRead == 0 {
                break
            }
            data.append(buffer, count: bytesRead)
        }

        return data
    }
}
