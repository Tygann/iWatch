import SwiftUI

struct AccountView: View {
    var body: some View {
        Form {
            Section {
                Label("Guest", systemImage: "person.crop.circle")
                    .font(.headline)
            } footer: {
                Text("You can use iWatch without an account.")
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AccountView()
    }
}
