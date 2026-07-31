import SwiftUI

struct ResetDataView: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router

    @State private var showEraseConfirmation = false

    var body: some View {
        Form {
            Section {
                Label("This permanently removes your iWatch library and preferences from this app and iCloud, then disconnects Trakt on this device.", systemImage: "exclamationmark.triangle")
            } header: {
                Text("Erase All App Data")
            } footer: {
                Text("This does not delete data stored in your Trakt account.")
            }

            Section {
                Button(
                    session.isErasingAllData ? "Erasing All App Data…" : "Erase All App Data",
                    role: .destructive
                ) {
                    showEraseConfirmation = true
                }
                .disabled(session.isErasingAllData || session.isSyncing)
            }
        }
        .navigationTitle("Reset iWatch")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Erase all iWatch data?",
            isPresented: $showEraseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Erase All Data", role: .destructive) {
                Task {
                    await session.eraseAllAppData()
                    router.resetToDefaults()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action can’t be undone. Your iWatch library will be removed from this app and iCloud.")
        }
    }
}

#Preview {
    let container = AppContainer.preview()
    NavigationStack {
        ResetDataView()
    }
    .environment(container.session)
    .environment(container.router)
}
