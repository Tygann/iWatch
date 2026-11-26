import AuthenticationServices
import PhotosUI
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
    @State private var draftPhoto: Data?
    @State private var isChoosingPhoto = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var cropSelection: AvatarCropSelection?
    @State private var isLoadingPhoto = false

    private var trimmedName: String? { AccountSession.validatedName(displayName) }

    private var nameChanged: Bool {
        if let trimmedName { return trimmedName != account.displayName }
        return !displayName.isEmpty || account.displayName != nil
    }

    private var canSave: Bool {
        !account.isBusy && !isLoadingPhoto && (!nameChanged || trimmedName != nil)
            && (nameChanged || draftPhoto != account.photo)
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: AppSpacing.medium) {
                    AccountAvatar(localPhoto: isEditing ? draftPhoto : account.photo, size: 100)
                        .overlay(alignment: .bottomTrailing) {
                            if isEditing, let ownerID = account.userID {
                                photoPicker(for: ownerID)
                                    .offset(x: 6, y: 4)
                            }
                        }
                    if isEditing, draftPhoto != nil {
                        Button(role: .destructive) {
                            draftPhoto = nil
                        } label: {
                            Text("Remove Photo")
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .disabled(isLoadingPhoto)
                    }
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
        .navigationBarBackButtonHidden(isEditing)
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: endEditing)
                        .disabled(account.isBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await saveEdits() } }
                        .disabled(!canSave)
                }
            } else if account.userID != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        displayName = account.displayName ?? ""
                        draftPhoto = account.photo
                        isEditing = true
                    }
                    .disabled(account.isBusy || account.profileFailed)
                }
            }
        }
        .photosPicker(isPresented: $isChoosingPhoto, selection: $pickedPhoto, matching: .images)
        .task(id: pickedPhoto) { await loadPickedPhoto(pickedPhoto) }
        .sheet(item: $cropSelection) { selection in
            AvatarCropView(selection: selection, account: account) { photo in
                guard isEditing, account.userID == selection.ownerID else { return }
                draftPhoto = photo
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

    private func photoPicker(for ownerID: UUID) -> some View {
        Button {
            choosePhoto(for: ownerID)
        } label: {
            Group {
                if isLoadingPhoto {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "pencil")
                        .font(.system(size: 16))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 30, height: 30)
            .glassEffect(.regular.interactive(), in: Circle())
            .frame(width: 44, height: 44, alignment: .bottomTrailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoadingPhoto)
        .accessibilityLabel(draftPhoto == nil ? "Add Photo" : "Change Photo")
    }

    private func choosePhoto(for ownerID: UUID) {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("UITEST_ACCOUNT_AVATAR") {
            let size = CGSize(width: 320, height: 240)
            let image = UIGraphicsImageRenderer(size: size).image { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                UIColor.systemOrange.setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 90, y: 50, width: 140, height: 140))
            }
            cropSelection = AvatarCropSelection(image: image, ownerID: ownerID)
            return
        }
        #endif
        isChoosingPhoto = true
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let ownerID = account.userID, isEditing else { return }
        isLoadingPhoto = true
        defer {
            if pickedPhoto == item {
                isLoadingPhoto = false
                pickedPhoto = nil
            }
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw AvatarImageService.PhotoError.unreadable
            }
            try Task.checkCancellation()
            guard account.userID == ownerID, pickedPhoto == item, isEditing else { return }
            cropSelection = AvatarCropSelection(image: try AvatarImageService.image(from: data), ownerID: ownerID)
        } catch {
            if !Task.isCancelled, pickedPhoto == item {
                account.message = "That photo couldn’t be opened. Try choosing another image."
            }
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
    }

    private func saveEdits() async {
        guard canSave, let ownerID = account.userID else { return }
        isNameFocused = false

        let changedName = nameChanged
        if changedName, !(await account.saveName(displayName)) { return }
        guard account.userID == ownerID, isEditing else { return }

        if draftPhoto != account.photo {
            do {
                try account.setPhoto(draftPhoto, for: ownerID)
            } catch {
                account.message = changedName
                    ? "Your username was saved. Couldn’t save the photo change. Please try again."
                    : "Couldn’t save the photo change. Please try again."
                return
            }
        }

        endEditing()
    }

    private func endEditing() {
        isNameFocused = false
        draftPhoto = nil
        isChoosingPhoto = false
        pickedPhoto = nil
        cropSelection = nil
        isLoadingPhoto = false
        isEditing = false
        displayName = ""
    }
}

#Preview {
    NavigationStack {
        AccountView(account: AccountSession())
    }
}
