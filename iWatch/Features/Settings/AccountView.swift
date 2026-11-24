import AuthenticationServices
import SwiftUI

struct AccountView: View {
    @Bindable var account: AccountSession
    @Environment(\.colorScheme) private var colorScheme
    @State private var nonce: String?
    @State private var displayName = ""
    @State private var isDeleting = false

    private var trimmedName: String? { AccountSession.validatedName(displayName) }

    var body: some View {
        Form {
            Section {
                VStack(spacing: AppSpacing.medium) {
                    AccountAvatar(size: 100)
                    Text(account.title)
                        .font(.title.bold())
                        .fontDesign(.rounded)
                    if account.userID == nil {
                        Text("You can use iWatch without an account.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.small)
            }
            .listRowBackground(Color.clear)

            if account.userID != nil {
                profileSection
                Section {
                    Button("Sign Out") { Task { await account.signOut() } }
                }
                Section {
                    Button("Delete Account", role: .destructive) { isDeleting = true }
                }
            } else if account.isAvailable {
                Section {
                    SignInWithAppleButton(.signIn) { request in
                        nonce = AccountSession.configureSignIn(request)
                    } onCompletion: { result in
                        let signInNonce = nonce
                        nonce = nil
                        Task { await account.signIn(result, nonce: signInNonce) }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 50)
                }
            }
        }
        .disabled(account.isBusy)
        .overlay {
            if account.isBusy { ProgressView().accessibilityLabel("Updating account") }
        }
        .onChange(of: account.displayName, initial: true) { _, name in displayName = name ?? "" }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isDeleting) {
            NavigationStack {
                Form {
                    Section {
                        Text("This permanently deletes your iWatch account and profile. Your watch history and watchlist stay in your library.")
                        SignInWithAppleButton(.continue) { _ in
                        } onCompletion: { result in
                            isDeleting = false
                            Task { await account.delete(result) }
                        }
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 50)
                    } footer: {
                        Text("Continue with Apple to confirm account deletion.")
                    }
                }
                .navigationTitle("Delete Account")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isDeleting = false }
                    }
                }
            }
        }
        .alert("Account", isPresented: Binding(
            get: { account.message != nil },
            set: { if !$0 { account.message = nil } }
        )) {
            Button("OK", role: .cancel) { account.message = nil }
        } message: {
            Text(account.message ?? "")
        }
    }

    private var profileSection: some View {
        Section("Profile") {
            if account.profileFailed {
                Text("Your profile couldn’t be loaded.")
                Button("Try Again") { Task { await account.refresh() } }
            } else {
                TextField("Display Name", text: $displayName)
                    .textContentType(.nickname)
                Button("Save Name") { Task { await account.saveName(displayName) } }
                    .disabled(trimmedName == nil || trimmedName == account.displayName)
            }
        }
    }
}

#Preview {
    NavigationStack {
        AccountView(account: AccountSession())
    }
}
