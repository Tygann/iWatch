import Foundation

public protocol TraktAuthStore: Sendable {
    func currentToken() async -> TokenResponse?
    func save(token: TokenResponse) async
    func clear() async
}

public actor InMemoryTraktAuthStore: TraktAuthStore {
    private var token: TokenResponse?

    public init() {}

    public func currentToken() async -> TokenResponse? { token }
    public func save(token: TokenResponse) async { self.token = token }
    public func clear() async { token = nil }
}

public nonisolated protocol DeviceIdentityStore: Sendable {
    func currentDeviceID() async -> String
}
