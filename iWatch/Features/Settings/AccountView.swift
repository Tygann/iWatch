import SwiftUI

struct AccountView: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: AppSpacing.medium) {
                    Circle()
                        .fill(.quaternary)
                        .frame(width: 100, height: 100)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityHidden(true)
                    Text("Guest")
                        .font(.title.bold())
                        .fontDesign(.rounded)
                    Text("You can use iWatch without an account.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.small)
            }
            .listRowBackground(Color.clear)
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
