import SwiftUI

struct SettingsView: View {
    @State private var iCloudOn: Bool = true   // SwiftData CloudKit is on by default in AppEnvironment
    @State private var traktConnected = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Sync") {
                    Toggle("iCloud Sync (SwiftData + CloudKit)", isOn: $iCloudOn)
                        .disabled(true)
                    HStack {
                        Text("Trakt")
                        Spacer()
                        if traktConnected {
                            Text("Connected").foregroundStyle(.secondary)
                        } else {
                            Button("Connect") { /* present auth */ }
                        }
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "iWatch")
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
