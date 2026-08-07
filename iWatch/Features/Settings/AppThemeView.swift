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

struct AppThemeView: View {
    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    var body: some View {
        Form {
            Section {
                ForEach(AppTheme.allCases) { theme in
                    Button {
                        appTheme = theme
                    } label: {
                        HStack {
                            Label(theme.title, systemImage: theme.systemImage)
                                .foregroundStyle(.primary)
                            Spacer()
                            if appTheme == theme {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .accessibilityAddTraits(appTheme == theme ? .isSelected : [])
                }
            } footer: {
                Text("System automatically follows your device’s appearance setting.")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AppThemeView()
    }
}
