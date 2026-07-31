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
                Picker("Appearance", selection: $appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Label(theme.title, systemImage: theme.systemImage)
                            .tag(theme)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("System automatically follows your device’s appearance setting.")
            }
        }
        .navigationTitle("App Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AppThemeView()
    }
}
