import SwiftUI

enum AdvancedSettingsSection: String, CaseIterable {
    case storage = "Storage"
    case reset = "Reset"
}

struct AdvancedSettingsView: View {
    var body: some View {
        Form {
            Section(AdvancedSettingsSection.storage.rawValue) {
                NavigationLink {
                    StorageSettingsView()
                } label: {
                    Label("Temporary Files", systemImage: "internaldrive")
                }
            }

            Section {
                NavigationLink {
                    ResetDataView()
                } label: {
                    Label("Erase All App Data", systemImage: "trash")
                }
            } header: {
                Text(AdvancedSettingsSection.reset.rawValue)
            } footer: {
                Text("Permanently removes your iWatch library and preferences from this app and iCloud.")
            }
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AdvancedSettingsView()
    }
}
