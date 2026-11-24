import Foundation
import Supabase

struct AccountBackend {
    struct Configuration {
        let url: URL
        let publishableKey: String

        init?(url: String?, publishableKey: String?) {
            guard let url, let parsed = URL(string: url), parsed.scheme == "https",
                  parsed.host != nil, let publishableKey,
                  publishableKey.hasPrefix("sb_publishable_") else { return nil }
            self.url = parsed
            self.publishableKey = publishableKey
        }
    }

    struct Profile: Codable {
        let id: UUID
        let displayName: String

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    private let client: SupabaseClient

    init(configuration: Configuration) {
        client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey,
            options: .init(auth: .init(emitLocalSessionAsInitialSession: true))
        )
    }

    var cachedUserID: UUID? { client.auth.currentSession?.user.id }

    var cachedAppleID: String? {
        client.auth.currentUser?.identities?.first { $0.provider == "apple" }?.id
    }

    func signIn(identityToken: String, nonce: String) async throws -> UUID {
        let session = try await client.auth.signInWithIdToken(credentials: .init(
            provider: .apple, idToken: identityToken, nonce: nonce
        ))
        return session.user.id
    }

    func profile(for id: UUID) async throws -> Profile? {
        let profiles: [Profile] = try await client.from("account_profiles")
            .select().eq("id", value: id).limit(1).execute().value
        return profiles.first
    }

    func saveProfile(_ profile: Profile) async throws {
        try await client.from("account_profiles").upsert(profile).execute()
    }

    func signOut() async throws {
        try await client.auth.signOut(scope: .local)
    }

    func deleteAccount(authorizationCode: String) async throws {
        try await client.functions.invoke("delete-account", options: .init(body: [
            "authorization_code": authorizationCode
        ]))
    }
}
