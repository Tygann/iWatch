import AuthenticationServices
import SwiftUI

struct AccountView: View {
    @Bindable var account: AccountSession
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var isNameFocused: Bool
    @State private var isEditing = false
    @State private var nonce: String?
    @State private var displayName = ""
    @State private var isDeleting = false

    private var trimmedName: String? { AccountSession.validatedName(displayName) }

    var body: some View {
        Form {
            Section {
                VStack(spacing: AppSpacing.medium) {
                    AccountAvatar(size: 100)
                    if !isEditing {
                        Text(account.title)
                            .font(.title.bold())
                            .fontDesign(.rounded)
                    }
                    if account.userID == nil {
                        Text("You can use iWatch without an account.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if account.isAvailable {
                            signInButton
                                .padding(.top, AppSpacing.small)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.small)
            }
            .listRowBackground(Color.clear)

            if account.userID != nil {
                if isEditing {
                    editSections
                } else {
                    if account.profileFailed {
                        Section {
                            Text("Your profile couldn’t be loaded.")
                            Button("Try Again") { Task { await account.refresh() } }
                        }
                    }
                    Section {
                        Button {
                            Task { await account.signOut() }
                        } label: {
                            Text("Sign Out").frame(maxWidth: .infinity)
                        }
                    }
                    Section {
                        Button(role: .destructive) {
                            isDeleting = true
                        } label: {
                            Text("Delete Account").frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .disabled(account.isBusy)
        .overlay {
            if account.isBusy { ProgressView().accessibilityLabel("Updating account") }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: account.userID) { _, _ in endEditing() }
        .navigationTitle(isEditing ? "Edit Account" : "Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if account.userID != nil {
                ToolbarItem(placement: .primaryAction) {
                    if isEditing {
                        Button("Cancel", action: endEditing)
                            .disabled(account.isBusy)
                    } else {
                        Button("Edit") {
                            displayName = account.displayName ?? ""
                            isEditing = true
                        }
                        .disabled(account.isBusy || account.profileFailed)
                    }
                }
            }
        }
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

    private var signInButton: some View {
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

    @ViewBuilder
    private var editSections: some View {
        Section {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.small))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: AppSpacing.medium))

            layout {
                Text("Username")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                TextField("Username", text: $displayName)
                    .textContentType(.nickname)
                    .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit { isNameFocused = false }
            }
        }

        Section {
            Button {
                isNameFocused = false
                Task {
                    if await account.saveName(displayName) {
                        endEditing()
                    }
                }
            } label: {
                Text("Save").frame(maxWidth: .infinity)
            }
            .disabled(trimmedName == nil || trimmedName == account.displayName)
        }
    }

    private func endEditing() {
        isNameFocused = false
        isEditing = false
        displayName = ""
    }
}

#Preview {
    NavigationStack {
        AccountView(account: AccountSession())
    }
}
