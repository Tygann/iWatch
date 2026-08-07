import SwiftUI

enum AppTheme: Int, CaseIterable, Identifiable {
    case system = 0
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

private struct ApplyAppTheme: ViewModifier {
    let theme: AppTheme

    func body(content: Content) -> some View {
        switch theme {
        case .system:
            content
        case .light:
            content.preferredColorScheme(.light)
        case .dark:
            content.preferredColorScheme(.dark)
        }
    }
}

extension View {
    func appTheme(_ theme: AppTheme) -> some View {
        modifier(ApplyAppTheme(theme: theme))
    }
}
