import SwiftUI
import StoreKit
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.requestReview) private var requestReview

    @AppStorage("hideEndedShows") private var hideEndedShows = false
    @State private var showResetSyncConfirmation = false
    @State private var showEraseAllAppDataConfirmation = false
    @State private var showTraktLinkDecision = false

    var body: some View {
        Form {
            syncSection
            preferencesSection
            aboutSection
        }
        .alert("Sync Error", isPresented: Binding(
            get: { session.traktLastError != nil },
            set: { if !$0 { session.traktLastError = nil } }
        )) {
            Button("OK", role: .cancel) {
                session.traktLastError = nil
            }
        } message: {
            Text(session.traktLastError ?? "Unknown error")
        }
        .confirmationDialog("Reset local Trakt sync cache?", isPresented: $showResetSyncConfirmation, titleVisibility: .visible) {
            Button("Reset Local Sync Cache", role: .destructive) {
                Task { await session.resetLocalTraktSyncCache() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes local Trakt-derived watchlist, history, and pending sync operations, then rebuilds them from Trakt on the next sync. Any unsynced local changes will be lost.")
        }
        .confirmationDialog("Erase all app data?", isPresented: $showEraseAllAppDataConfirmation, titleVisibility: .visible) {
            Button("Erase All Data", role: .destructive) {
                Task {
                    await session.eraseAllAppData()
                    router.resetToDefaults()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This erases iWatch data from the app and iCloud sync storage, signs out of Trakt on this device, and resets app preferences. It does not delete your Trakt account data.")
        }
        .confirmationDialog("Set up Trakt sync", isPresented: $showTraktLinkDecision, titleVisibility: .visible) {
            Button("Import Trakt Library") { Task { await session.importTraktLibrary() } }
            Button("Upload Local Library") { Task { await session.uploadLocalLibrary() } }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Import keeps Trakt as the source of truth. Upload sends your existing local watchlist and history to this Trakt account.")
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await session.refreshSyncDiagnostics()
            showTraktLinkDecision = session.pendingTraktAccountKey != nil
        }
        .onChange(of: session.pendingTraktAccountKey) { _, key in
            showTraktLinkDecision = key != nil
        }
    }

    private var syncSection: some View {
        Section {
            LabeledContent("iCloud") {
                Text("Enabled")
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Trakt") {
                if session.traktConnected {
                    Text("Connected")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not Connected")
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("Redirect URI") {
                Text(session.traktRedirectURI)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            if let lastSyncAt = session.lastSyncAt {
                LabeledContent("Last Sync") {
                    Text(lastSyncAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("Baseline") {
                Text(session.syncDiagnostics.initialBaselineComplete ? "Ready" : "Pending")
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Outbox") {
                if session.syncDiagnostics.hasPendingWork {
                    Text("\(session.syncDiagnostics.pendingOperationCount) pending, \(session.syncDiagnostics.processingOperationCount) processing")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Idle")
                        .foregroundStyle(.secondary)
                }
            }

            if session.syncDiagnostics.deadletterOperationCount > 0 {
                LabeledContent("Failed Ops") {
                    Text("\(session.syncDiagnostics.deadletterOperationCount)")
                        .foregroundStyle(.red)
                }
            }

            if session.syncDiagnostics.duplicateCandidateCount > 0 {
                LabeledContent("Local Duplicates") {
                    Text("\(session.syncDiagnostics.duplicateCandidateCount)")
                        .foregroundStyle(.orange)
                }
            }

            if let lastRemoteActivityAt = session.syncDiagnostics.lastSeenRemoteActivityAt {
                LabeledContent("Last Remote Change") {
                    Text(lastRemoteActivityAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }

            if session.traktConnected {
                Button {
                    Task { await session.runSync(reason: .userInitiated) }
                } label: {
                    Label(session.isSyncing ? "Syncing…" : "Sync Now", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                }
                .disabled(session.isSyncing || session.isErasingAllData)

                if session.syncDiagnostics.deadletterOperationCount > 0 {
                    Button {
                        Task { await session.retryFailedSyncOperations() }
                    } label: {
                        Label("Retry Failed Operations", systemImage: "arrow.clockwise")
                    }
                    .disabled(session.isSyncing || session.isErasingAllData)
                }

                Button {
                    Task { await session.repairLocalSyncData() }
                } label: {
                    Label("Repair Local Sync Data", systemImage: "cross.case")
                }
                .disabled(session.isSyncing || session.isErasingAllData)

                Button(role: .destructive) {
                    showResetSyncConfirmation = true
                } label: {
                    Label("Reset Local Trakt Sync Cache", systemImage: "arrow.counterclockwise")
                }
                .disabled(session.isSyncing || session.isErasingAllData)

                Button(role: .destructive) {
                    session.logoutTrakt()
                } label: {
                    Label("Disconnect Trakt", systemImage: "xmark.circle")
                }
                .disabled(session.isErasingAllData)
            } else {
                Button {
                    session.startTraktOAuth()
                } label: {
                    Label(session.traktIsConnecting ? "Connecting…" : "Connect Trakt", systemImage: "link")
                }
                .disabled(session.traktIsConnecting || session.isErasingAllData)
            }

            Button(role: .destructive) {
                showEraseAllAppDataConfirmation = true
            } label: {
                Label(session.isErasingAllData ? "Erasing All App Data…" : "Erase All App Data", systemImage: "trash")
            }
            .disabled(session.isErasingAllData || session.isSyncing)
        } header: {
            Text("Sync")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("CloudKit keeps your local database in sync across devices. Trakt sync runs separately with a pull, merge, then push flow.")
                Text("If Trakt sign-in fails, verify the redirect URI above exactly matches the redirect URI configured in your Trakt API app settings.")
                if let message = session.syncMaintenanceMessage {
                    Text(message)
                } else if let lastError = session.syncDiagnostics.lastErrorDescription {
                    Text(lastError)
                }
            }
        }
    }

    private var preferencesSection: some View {
        Section {
            Picker("Default Tab", selection: Binding(
                get: { router.selectedTab.rawValue },
                set: { router.updateDefaultTab($0) }
            )) {
                Text("Movies").tag(AppRouter.Tab.movies.rawValue)
                Text("Shows").tag(AppRouter.Tab.shows.rawValue)
                Text("Search").tag(AppRouter.Tab.search.rawValue)
            }

            Toggle("Hide Ended Shows", isOn: $hideEndedShows)

            NavigationLink {
                AppThemeView()
            } label: {
                Label("App Theme", systemImage: "paintbrush.pointed")
            }

            Button {
                Task {
                    await session.clearCache()
                    Haptics.notification(.success)
                }
            } label: {
                Label(session.isClearingCache ? "Clearing Cache…" : "Clear Cache", systemImage: "trash")
            }
            .disabled(session.isClearingCache || session.isErasingAllData)
        } header: {
            Text("Preferences")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Clears temporary files like downloaded artwork and network responses. Your library and sync data stay intact.")
                if let message = session.cacheMaintenanceMessage {
                    Text(message)
                }
            }
        }
    }

    private var aboutSection: some View {
        Section {
            NavigationLink {
                AboutView()
            } label: {
                Label("About iWatch", systemImage: "info.circle")
            }

            Button {
                requestReview()
            } label: {
                Label("Rate App", systemImage: "star")
            }

            Button {
                shareApp()
            } label: {
                Label("Share App", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("About")
        }
    }

    private func shareApp() {
        guard let url = URL(string: "https://apps.apple.com/us/app/renfo/id6502414968") else { return }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let controller = windowScene.windows.first?.rootViewController else {
            return
        }

        controller.present(activityVC, animated: true)
    }
}

#Preview {
    let container = AppContainer.preview()
    NavigationStack {
        SettingsView()
    }
    .environment(container)
    .environment(container.session)
    .environment(container.router)
    .modelContainer(container.persistence.modelContainer)
}
