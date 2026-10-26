import SwiftUI

/// One interpretation of sync health shared by Settings and every Trakt subview.
struct TraktSyncPresentation: Equatable {
    enum Action { case connect, setup, sync, check, retry }
    let title: String
    let detail: String
    let symbol: String
    let needsAttention: Bool
    let isWorking: Bool
    let action: Action

    static func resolve(connected: Bool, connecting: Bool, settingUp: Bool, syncing: Bool,
                        progress: SyncProgress, diagnostics: SyncDiagnostics, error: String?, maintenanceTitle: String? = nil) -> Self {
        if connecting {
            return Self(title: "Connecting…", detail: "Finish signing in to Trakt to continue.", symbol: "person.crop.circle", needsAttention: false, isWorking: true, action: .connect)
        }
        if !connected {
            return Self(title: error == nil ? "Not Connected" : "Sign In to Trakt", detail: error == nil
                ? "Connect Trakt to sync your Watchlist and watched history. Your library stays available in iWatch."
                : "Your Trakt connection needs attention. Sign in to continue syncing.", symbol: "person.crop.circle", needsAttention: error != nil, isWorking: false, action: .connect)
        }
        if let maintenanceTitle, !syncing {
            return Self(title: maintenanceTitle, detail: "Keep iWatch open while this finishes.", symbol: "arrow.triangle.2.circlepath", needsAttention: false, isWorking: true, action: .sync)
        }
        if settingUp {
            return Self(title: error == nil ? "Finish Setup" : "Setup Needs Attention", detail: error == nil ? "Choose how to start syncing this Trakt account." : "iWatch couldn’t finish setting up this account. Try again, or disconnect to choose another account.", symbol: "person.crop.circle.badge.checkmark", needsAttention: true, isWorking: false, action: .setup)
        }
        if syncing {
            return Self(title: "Syncing…", detail: [progress.title, progress.detail].compactMap { $0 }.joined(separator: "\n"), symbol: "arrow.triangle.2.circlepath", needsAttention: false, isWorking: true, action: .sync)
        }
        if diagnostics.failure == .offline {
            return Self(title: "Connection Interrupted", detail: "iWatch couldn’t reach Trakt. Your local changes are saved. Try again when your connection is available.", symbol: "wifi.exclamationmark", needsAttention: true, isWorking: false, action: .sync)
        }
        if diagnostics.failure == .ambiguous {
            return Self(title: "Review Watched History", detail: "iWatch couldn’t match a watched change to a single Trakt play. Review your history on Trakt. iWatch won’t send the play again.", symbol: "exclamationmark.triangle", needsAttention: true, isWorking: false, action: .check)
        }
        if diagnostics.changes.contains(where: { $0.state == .confirming }) || diagnostics.failure == .confirmation {
            return Self(title: "Waiting for Confirmation", detail: "A watched change is saved in iWatch, but its upload hasn’t been confirmed. Checking again won’t send another watched play.", symbol: "clock.badge.exclamationmark", needsAttention: true, isWorking: false, action: .check)
        }
        if diagnostics.deadletterOperationCount > 0 || error != nil || diagnostics.lastErrorDescription != nil {
            return Self(title: "Sync Needs Attention", detail: "Some changes couldn’t be synced. Review pending changes or try again. Your library remains available in iWatch.", symbol: "exclamationmark.triangle", needsAttention: true, isWorking: false,
                        action: diagnostics.changes.contains { $0.state == .failed && $0.isOnThisDevice } ? .retry : .sync)
        }
        if diagnostics.duplicateCandidateCount > 0 {
            return Self(title: "Library Check Recommended", detail: "Local library data may need attention. You can check it in Advanced.", symbol: "exclamationmark.triangle", needsAttention: true, isWorking: false, action: .sync)
        }
        if diagnostics.hasPendingWork {
            return Self(title: "Changes Pending", detail: "Your changes are saved in iWatch and waiting to sync. Changes made on another device upload from that device.", symbol: "clock", needsAttention: false, isWorking: false, action: .sync)
        }
        return Self(title: diagnostics.initialBaselineComplete ? "Sync Complete" : "Ready to Sync",
                    detail: "Your Watchlist and watched history sync automatically with Trakt.", symbol: "checkmark.circle", needsAttention: false, isWorking: false, action: .sync)
    }
}

extension AppSession {
    var traktSyncPresentation: TraktSyncPresentation {
        var diagnostics = syncDiagnostics
        if traktConnectionInterrupted { diagnostics.failure = .offline }
        return .resolve(connected: traktConnected, connecting: traktIsConnecting,
                 settingUp: pendingTraktAccountKey != nil, syncing: isSyncing,
                 progress: syncProgress, diagnostics: diagnostics, error: traktLastError, maintenanceTitle: syncMaintenanceTitle)
    }

    var syncActionsUnavailable: Bool {
        isSyncing || isMaintainingSync || isErasingAllData || traktIsConnecting
    }
}

/// Full-width explanatory content avoids squeezing messages into trailing value columns.
struct SyncStatusContent: View {
    let title: String
    let detail: String
    let symbol: String
    var needsAttention = false
    var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title).font(.headline)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(needsAttention ? Color.orange : Color.accentColor)
            }
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
            if isWorking {
                ProgressView().accessibilityLabel(title)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct SyncDateRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    let date: Date

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            LabeledContent(title, value: date.formatted(date: .abbreviated, time: .shortened))
        }
    }
}
