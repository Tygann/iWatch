import Foundation

enum AppDistributionPresentation {
    // Replace the TestFlight URL with the public App Store product URL after release.
    static let publicInstallURL = URL(string: "https://testflight.apple.com/join/r6MFxreq")!

    static var shareText: String {
        let introduction = "iWatch helps you track the movies and shows you care about."
        return "\(introduction) \(publicInstallURL.absoluteString)"
    }
}
