import SwiftUI

struct StorageSettingsView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Form {
            Section {
                Button {
                    Task {
                        await session.clearCache()
                        Haptics.notification(.success)
                    }
                } label: {
                    HStack {
                        Label("Clear Temporary Files", systemImage: "trash")
                        Spacer()
                        if session.isClearingCache {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(session.isClearingCache || session.isErasingAllData)
            } footer: {
                Text("Removes downloaded artwork and cached network responses. Your library, preferences, iCloud data, and Trakt data are not affected.")
            }

            if let message = session.cacheMaintenanceMessage {
                Section("Latest Result") {
                    Text(message)
                }
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let container = AppContainer.preview()
    NavigationStack {
        StorageSettingsView()
    }
    .environment(container.session)
}
