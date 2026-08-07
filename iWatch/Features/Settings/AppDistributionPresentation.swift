import Foundation

enum AppDistributionPresentation {
    // Add the public App Store product URL after iWatch is available for download.
    static let appStoreURL: URL? = nil

    static var shareText: String {
        let introduction = "iWatch helps you track the movies and shows you care about."
        guard let appStoreURL else {
            return introduction
        }
        return "\(introduction) \(appStoreURL.absoluteString)"
    }
}
