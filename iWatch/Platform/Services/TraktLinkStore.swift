import Foundation

enum TraktLinkStore {
    private nonisolated static let accountDefaultsKey = "trakt.activeAccountKey"

    nonisolated static var activeAccountKey: String? {
        get { UserDefaults.standard.string(forKey: accountDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: accountDefaultsKey) }
    }

    nonisolated static func clear() { UserDefaults.standard.removeObject(forKey: accountDefaultsKey) }
}
