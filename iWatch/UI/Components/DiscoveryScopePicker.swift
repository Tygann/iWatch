import SwiftUI

struct DiscoveryScopePicker<SelectionValue: Hashable, Content: View>: View {
    private let title: LocalizedStringKey
    @Binding private var selection: SelectionValue
    private let content: Content

    init(
        _ title: LocalizedStringKey,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        _selection = selection
        self.content = content()
    }

    var body: some View {
        Picker(title, selection: $selection) {
            content
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
}
