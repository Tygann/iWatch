// App/Services/AuthService.swift
import Foundation
import Security
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#endif

/// Centralized auth storage implementations for Trakt.
/// TokenResponse and TraktAuthStore are defined elsewhere in the project.

public actor KeychainTraktAuthStore: TraktAuthStore {
    private let service = "com.trakt.token"
    private let account = "default"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {}

    public func currentToken() async -> TokenResponse? {
        guard let data = await readKeychain(service: service, account: account) else {
            print("[Keychain] Read token: no data found")
            return nil
        }
        do {
            // If TokenResponse's Decodable conformance is @MainActor-isolated (Swift 6 rule),
            // perform the decode on the main actor to satisfy isolation.
            let token: TokenResponse = try await MainActor.run { [decoder] in
                try decoder.decode(TokenResponse.self, from: data)
            }
            print("[Keychain] Read token: successfully decoded token")
            return token
        } catch {
            print("[Keychain] Decode error: \(error)")
            return nil
        }
    }

    public func save(token: TokenResponse) async {
        // If TokenResponse's Encodable conformance is @MainActor-isolated, encode on the main actor.
        let data: Data? = await MainActor.run { [encoder] in
            try? encoder.encode(token)
        }
        guard let data else { return }

        if let jsonString = String(data: data, encoding: .utf8) {
            print("[Keychain] Save token: \(jsonString)")
        } else {
            print("[Keychain] Save token: unable to convert token data to JSON string")
        }

        if await readKeychain(service: service, account: account) != nil {
            let success = await updateKeychain(data: data, service: service, account: account)
            print("[Keychain] Update keychain \(success ? "succeeded" : "failed")")
        } else {
            let addResult = await addKeychain(data: data, service: service, account: account)
            switch addResult {
            case .success:
                print("[Keychain] Add keychain succeeded")
            case .duplicate:
                let success = await updateKeychain(data: data, service: service, account: account)
                print("[Keychain] Add keychain found duplicate, update keychain \(success ? "succeeded" : "failed")")
            case .failure(let status):
                print("[Keychain] Add keychain failed: \(status)")
            }
        }
    }

    public func clear() async {
        _ = await deleteKeychain(service: service, account: account)
    }

    private enum AddKeychainResult {
        case success
        case duplicate
        case failure(OSStatus)
    }

    private func addKeychain(data: Data, service: String, account: String) async -> AddKeychainResult {
        let status: OSStatus = await MainActor.run {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
                // Access after first unlock; not synced to other devices
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            return SecItemAdd(query as CFDictionary, nil)
        }
        #if DEBUG
        if status != errSecSuccess && status != errSecDuplicateItem {
            print("[Keychain] SecItemAdd failed: \(status)")
        }
        #endif
        if status == errSecDuplicateItem {
            return .duplicate
        }
        return status == errSecSuccess ? .success : .failure(status)
    }

    private func updateKeychain(data: Data, service: String, account: String) async -> Bool {
        let status: OSStatus = await MainActor.run {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: data,
                // Keep the same accessibility class explicit on update
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            return SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        }
        #if DEBUG
        if status != errSecSuccess {
            print("[Keychain] SecItemUpdate failed: \(status)")
        }
        #endif
        return status == errSecSuccess
    }

    private func readKeychain(service: String, account: String) async -> Data? {
        await MainActor.run {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            guard status == errSecSuccess else { return nil }
            return item as? Data
        }
    }

    private func deleteKeychain(service: String, account: String) async -> Bool {
        await MainActor.run {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
    }
}

public actor KeychainDeviceIdentityStore: DeviceIdentityStore {
    private let service = "com.tyler.iwatch.device"
    private let account = "primary"

    public init() {}

    public func currentDeviceID() async -> String {
        if let data = await readKeychain(service: service, account: account),
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            return value
        }

        let value = UUID().uuidString.lowercased()
        let data = Data(value.utf8)

        if await readKeychain(service: service, account: account) != nil {
            _ = await updateKeychain(data: data, service: service, account: account)
        } else {
            let result = await addKeychain(data: data, service: service, account: account)
            if case .duplicate = result {
                _ = await updateKeychain(data: data, service: service, account: account)
            }
        }

        return value
    }

    private enum AddKeychainResult {
        case success
        case duplicate
        case failure(OSStatus)
    }

    private func addKeychain(data: Data, service: String, account: String) async -> AddKeychainResult {
        let status: OSStatus = await MainActor.run {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            return SecItemAdd(query as CFDictionary, nil)
        }

        if status == errSecDuplicateItem {
            return .duplicate
        }
        return status == errSecSuccess ? .success : .failure(status)
    }

    private func updateKeychain(data: Data, service: String, account: String) async -> Bool {
        let status: OSStatus = await MainActor.run {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            return SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        }
        return status == errSecSuccess
    }

    private func readKeychain(service: String, account: String) async -> Data? {
        await MainActor.run {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            guard status == errSecSuccess else { return nil }
            return item as? Data
        }
    }
}

enum OAuthStateGenerator {
    static func make(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }

        let data = Data(bytes)
        return data
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Trakt OAuth Presentation Utilities (iOS)
#if canImport(UIKit)

@MainActor
final class TraktWebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // 1) Prefer the key, visible window in a foreground-active scene
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows
            .first(where: { !$0.isHidden && $0.isKeyWindow }) {
            return window
        }

        // 2) Fallback: any visible window in any foreground-active scene
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive })
            .flatMap({ $0.windows })
            .first(where: { !$0.isHidden }) {
            return window
        }

        // 3) Fallback: construct an anchor from a foreground-active scene
        if let activeScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            return ASPresentationAnchor(windowScene: activeScene)
        }

        // 4) Fallback: construct an anchor from any available scene (not ideal, but avoids deprecated APIs)
        if let anyScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first {
            assertionFailure("[OAuth] Using non-foreground UIWindowScene as presentation anchor fallback")
            return ASPresentationAnchor(windowScene: anyScene)
        }

        // 5) Absolute last resort: fail loudly rather than using the deprecated empty anchor initializer.
        preconditionFailure("[OAuth] No UIWindowScene or UIWindow available for presentation anchor")
    }
}

@MainActor
final class TraktAuthCoordinator {
    private var session: ASWebAuthenticationSession?
    private let presenter = TraktWebAuthPresenter()

    func start(authURL: URL,
               callbackScheme: String,
               prefersEphemeral: Bool = true,
               completion: @escaping (URL?, Error?) -> Void) {
        // Present after a window is available
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let s = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { [weak self] url, error in
                completion(url, error)
                self?.session = nil
            }
            s.presentationContextProvider = self.presenter
            if #available(iOS 13.4, *) {
                s.prefersEphemeralWebBrowserSession = prefersEphemeral
            }
            self.session = s
            _ = s.start()
        }
    }
}

#endif

// (Optional) Placeholder for other auth utilities
// final class AuthService { }
