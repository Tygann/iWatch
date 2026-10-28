import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    enum Tab: Int {
        case movies = 0
        case shows = 1
        case search = 2
    }

    private let defaults: UserDefaults
    private(set) var defaultTab: Tab
    var selectedTab: Tab
    var isShowingSettings = false

    init(defaultTab: Int? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let tab = Tab(rawValue: defaultTab ?? defaults.integer(forKey: "defaultTab")) ?? .movies
        self.defaultTab = tab
        self.selectedTab = tab
    }

    func updateDefaultTab(_ value: Int) {
        defaultTab = Tab(rawValue: value) ?? .movies
        defaults.set(defaultTab.rawValue, forKey: "defaultTab")
    }

    func resetToDefaults() {
        defaults.removeObject(forKey: "defaultTab")
        defaultTab = .movies
        selectedTab = .movies
    }
}
