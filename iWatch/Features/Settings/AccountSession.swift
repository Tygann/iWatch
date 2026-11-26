import AuthenticationServices
import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class AccountSession {
    private let backend: AccountBackend?
    private(set) var userID: UUID?
    private(set) var displayName: String?
    private(set) var isBusy = false
    private(set) var profileFailed = false
    var message: String?

    var isAvailable: Bool { backend != nil }
    var title: String { displayName ?? (userID == nil ? "Guest" : "Account") }

    init(backend: AccountBackend? = nil) {
        self.backend = backend
        userID = backend?.cachedUserID
    }

    #if DEBUG
    convenience init(previewDisplayName: String) {
        self.init()
        userID = UUID()
        displayName = previewDisplayName
    }
    #endif

    func refresh() async {
        guard let backend, !isBusy else { return }
        let cachedID = backend.cachedUserID
        if userID != cachedID {
            displayName = nil
            userID = cachedID
        }
        guard let cachedID else { return }
        isBusy = true
        defer { isBusy = false }
        if let appleID = backend.cachedAppleID,
           let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: appleID),
           state == .revoked || state == .notFound {
            try? await backend.signOut()
            clear()
            return
        }
        await loadProfile(from: backend, for: cachedID)
    }

    func signIn(_ result: Result<ASAuthorization, any Error>, nonce: String?) async {
        guard let backend, userID == nil, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let credential = try result.get().credential
            guard let apple = credential as? ASAuthorizationAppleIDCredential,
                  let data = apple.identityToken, let token = String(data: data, encoding: .utf8),
                  let nonce else {
                message = "Apple sign-in couldn’t be completed. Please try again."
                return
            }
            let id = try await backend.signIn(identityToken: token, nonce: nonce)
            userID = id
            await loadProfile(from: backend, for: id)
        } catch let error as ASAuthorizationError where error.code == .canceled {
        } catch {
            message = "Couldn’t sign in. Please try again."
        }
    }

    func saveName(_ name: String) async -> Bool {
        guard let backend, let userID, !isBusy, let trimmed = Self.validatedName(name) else {
            return false
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await backend.saveProfile(.init(id: userID, displayName: trimmed))
            displayName = trimmed
            profileFailed = false
            return true
        } catch {
            message = "Couldn’t save your name. Please try again."
            return false
        }
    }

    func signOut() async {
        guard let backend, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await backend.signOut()
            clear()
        } catch {
            if backend.cachedUserID == nil { clear() }
            else { message = "Couldn’t sign out. Please try again." }
        }
    }

    func delete(_ result: Result<ASAuthorization, any Error>) async {
        guard let backend, userID != nil, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let credential = try result.get().credential
            guard let apple = credential as? ASAuthorizationAppleIDCredential,
                  let data = apple.authorizationCode, let code = String(data: data, encoding: .utf8) else {
                message = "Apple couldn’t confirm your identity. Please try again."
                return
            }
            try await backend.deleteAccount(authorizationCode: code)
            try? await backend.signOut()
            clear()
        } catch let error as ASAuthorizationError where error.code == .canceled {
        } catch {
            message = "Couldn’t delete your account. Please try again."
        }
    }

    static func validatedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...80).contains(trimmed.unicodeScalars.count) ? trimmed : nil
    }

    static func configureSignIn(_ request: ASAuthorizationAppleIDRequest) -> String {
        let nonce = UUID().uuidString + UUID().uuidString
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
        return nonce
    }

    private func loadProfile(from backend: AccountBackend, for id: UUID) async {
        do {
            displayName = try await backend.profile(for: id)?.displayName
            profileFailed = false
        } catch {
            if backend.cachedUserID == nil { clear() }
            else { profileFailed = true }
        }
    }

    private func clear() {
        userID = nil
        displayName = nil
        profileFailed = false
    }
}
