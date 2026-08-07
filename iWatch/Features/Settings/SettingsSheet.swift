import SwiftData
import SwiftUI

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .close) {
                            dismiss()
                        }
                        .accessibilityLabel("Close Settings")
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }
}

#Preview {
    let container = AppContainer.preview()
    SettingsSheet()
        .environment(container)
        .environment(container.session)
        .environment(container.router)
        .modelContainer(container.persistence.modelContainer)
}
