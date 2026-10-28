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

struct SettingsNavigationLabel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let systemImage: String
    var detail: String?

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            stackedCopy
        } else {
            Label {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(title).fixedSize()
                        Spacer(minLength: AppSpacing.medium)
                        if let detail {
                            Text(detail).foregroundStyle(.secondary).fixedSize()
                        }
                    }
                    stackedCopy
                }
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                    .accessibilityHidden(true)
            }
        }
    }

    private var stackedCopy: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text(title)
            if let detail {
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
