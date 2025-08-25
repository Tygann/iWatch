import Foundation
import AuthenticationServices
import UIKit

/// Placeholder for future Trakt OAuth (PKCE) implementation.
final class TraktAuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let windowScene: UIWindowScene

    /// Initialize with a UIWindowScene (required for authentication presentation)
    init(windowScene: UIWindowScene) {
        self.windowScene = windowScene
        super.init()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor(windowScene: windowScene)
    }
    
    // TODO: Implement OAuth with PKCE, store tokens in Keychain
}

// Usage example:
// let authManager = TraktAuthManager(windowScene: currentWindowScene)



//import Foundation
//import AuthenticationServices
//
///// Placeholder for future Trakt OAuth (PKCE) implementation.
//final class TraktAuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {
//    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
//        return ASPresentationAnchor()
//    }
//
//    // TODO: Implement OAuth with PKCE, store tokens in Keychain
//}


//import UIKit
//import AuthenticationServices
//
//final class TraktAuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {
//    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
//        // Safely grab the first connected UIWindowScene
//        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
//            return ASPresentationAnchor(windowScene: scene)
//        }
//        // Fallback (shouldn't usually happen in a running app)
//        return ASPresentationAnchor()
//    }
//}
