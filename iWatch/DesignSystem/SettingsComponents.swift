import SwiftUI

enum AppSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 24
}

enum AppRadius {
    static let control: CGFloat = 12
    static let card: CGFloat = 16
}

struct SettingsCapsule: View {
    let title: String
    var tint: Color = .accentColor

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, AppSpacing.small)
            .padding(.vertical, AppSpacing.xSmall)
            .background(tint.opacity(0.12), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}
