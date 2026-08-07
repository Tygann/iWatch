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

    var selectedTab: Tab
    var isShowingSettings = false

    init(defaultTab: Int = UserDefaults.standard.integer(forKey: "defaultTab")) {
        self.selectedTab = Tab(rawValue: defaultTab) ?? .movies
    }

    func updateDefaultTab(_ value: Int) {
        UserDefaults.standard.set(value, forKey: "defaultTab")
        selectedTab = Tab(rawValue: value) ?? .movies
    }

    func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: "defaultTab")
        selectedTab = .movies
    }
}
