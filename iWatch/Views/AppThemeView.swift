import SwiftUI

// MARK: - App Theme Enumeration
enum AppTheme: Int, CaseIterable, Identifiable {
    case system = 0, light, dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

// MARK: - App Theme Modifier
private struct ApplyAppTheme: ViewModifier {
    let theme: AppTheme

    func body(content: Content) -> some View {
        switch theme {
        case .system:
            content                                  // no override
        case .light:
            content.preferredColorScheme(.light)     // force light
        case .dark:
            content.preferredColorScheme(.dark)      // force dark
        }
    }
}

extension View {
    func appTheme(_ theme: AppTheme) -> some View {
        modifier(ApplyAppTheme(theme: theme))
    }
}
// MARK: - Theme Change View
struct AppThemeView: View {
    @Environment(\.colorScheme) private var systemColorScheme

    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    // MARK: - View Body
    var body: some View {
        VStack(spacing: 50) {
            themeCircle
            themeTitle
            themePicker
        }
    }

    // Sun/Moon Theme Circle
    private var themeCircle: some View {
        Circle()
            .fill(LinearGradient(
                gradient: Gradient(colors: currentTheme.gradientColors),
                startPoint: .topTrailing,
                endPoint: .bottom))
            .frame(width: 150, height: 150)
            .overlay(
                Circle()
                    .offset(currentTheme.circleOffset)
                    .blendMode(.destinationOut)
                    .animation(.easeInOut, value: currentTheme.circleOffset)
            )
            .compositingGroup()
    }

    // Theme View Title
    private var themeTitle: some View {
        Text("Choose a style")
            .font(.title2)
            .fontWeight(.bold)
//            .customAttribute(AppearanceEffectRenderer)
    }

    // Custom Theme Picker
    private var themePicker: some View {
        Capsule()
            .fill(currentTheme.pickerColor)
            .padding(.horizontal, 100)
            .offset(x: currentTheme.pickerOffset)
            .padding(3)
            .background(Capsule().fill(.gray.tertiary))
//            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .frame(width: 300, height: 44)
            .overlay {
                HStack {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title)
                            .frame(maxWidth: .infinity)
                            .foregroundColor(appTheme == theme ? .primary : .secondary)
                            .onTapGesture {
                                withAnimation {
                                    appTheme = theme
                                }
                            }
                    }
                }
            }
    }

    // Testing theme picker with matchedgeometryeffect
    enum SegmentedControlState: String, CaseIterable {
            case option1 = "System"
            case option2 = "Light"
            case option3 = "Dark"
    }

    @State private var state: SegmentedControlState = .option1
    @Namespace private var segmentedControl

    private var themePickerT: some View {
        HStack {
            ForEach(SegmentedControlState.allCases, id: \.self) { item in
                Text(item.rawValue)
                    .padding(10)
                    .foregroundColor(state == item ? .white : .gray)
                    .matchedGeometryEffect(id: item, in: segmentedControl)
                    .onTapGesture {
                        withAnimation {
                            self.state = item
                        }
                    }
            }
        }
        .padding(3)
        .background(
            Capsule().fill(.gray.tertiary)
                .overlay(
                    Capsule().fill(.gray.tertiary)
                        .matchedGeometryEffect(id: state, in: segmentedControl, isSource: false)
                        .padding(.horizontal, 200)
                )
        )
    }

    // Combined computed property for gradient colors, overlay offset, picker offset
    private var currentTheme: (gradientColors: [Color], circleOffset: CGSize, pickerOffset: CGFloat, pickerColor: Color) {
        switch appTheme {
        case .system:
            return systemColorScheme == .dark
                ? ([.blue, .purple], CGSize(width: 30, height: -25), -100, .primary.opacity(0.1))
                : ([.orange, .red], CGSize(width: 110, height: -110), -100, .white)
        case .light:
            return ([.orange, .red], CGSize(width: 110, height: -110), 0, .white)
        case .dark:
            return ([.blue, .purple], CGSize(width: 30, height: -25), 100, .gray.opacity(0.4))
        }
    }
}

// MARK: - Preview Provider
#Preview {
    AppThemeView()
}
