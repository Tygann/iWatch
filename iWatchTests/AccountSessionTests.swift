import AuthenticationServices
import CryptoKit
import Foundation
import Testing
@testable import iWatch

@MainActor
struct AccountSessionTests {
    @Test
    func guestIsAvailableWithoutBackendConfiguration() async {
        let account = AccountSession()
        await account.refresh()
        #expect(!account.isAvailable)
        #expect(account.title == "Guest")
        #expect(account.userID == nil)
    }

    @Test
    func displayNameUsesDatabaseCharacterLimitAfterTrimming() {
        #expect(AccountSession.validatedName("  Taylor  ") == "Taylor")
        #expect(AccountSession.validatedName(" \n ") == nil)
        let family = "👨‍👩‍👧‍👦"
        #expect(AccountSession.validatedName(String(repeating: family, count: 11)) != nil)
        #expect(AccountSession.validatedName(String(repeating: family, count: 12)) == nil)
    }

    @Test
    func appleRequestUsesHashOfFreshNonce() {
        let provider = ASAuthorizationAppleIDProvider()
        let first = provider.createRequest()
        let second = provider.createRequest()

        let firstNonce = AccountSession.configureSignIn(first)
        let secondNonce = AccountSession.configureSignIn(second)
        let digest = SHA256.hash(data: Data(firstNonce.utf8))
            .map { String(format: "%02x", $0) }.joined()

        #expect(first.nonce == digest)
        #expect(firstNonce != secondNonce)
        #expect(first.nonce != second.nonce)
    }
}
