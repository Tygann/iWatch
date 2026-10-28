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

    var rowTitle: String {
        if action == .connect, !isWorking, !needsAttention { return "Trakt" }
        return title == "Sync Complete" ? "Trakt" : title
    }

    static func resolve(connected: Bool, connecting: Bool, settingUp: Bool, syncing: Bool,
                        progress: SyncProgress, diagnostics: SyncDiagnostics, error: String?, maintenanceTitle: String? = nil) -> Self {
        if connecting {
            return Self(title: "Connecting…", detail: "Finish signing in to continue.", symbol: "person.crop.circle", needsAttention: false, isWorking: true, action: .connect)
        }
        if !connected {
            return Self(title: error == nil ? "Not Connected" : "Sign In to Trakt", detail: error == nil
                ? "Sync your Watchlist and watched history."
                : "Sign in again to continue syncing.", symbol: "person.crop.circle", needsAttention: error != nil, isWorking: false, action: .connect)
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
            return Self(title: "Connection Interrupted", detail: "Try again when your connection is available.", symbol: "wifi.exclamationmark", needsAttention: true, isWorking: false, action: .sync)
        }
        if diagnostics.failure == .ambiguous {
            return Self(title: "Review Watched History", detail: "Review the matching plays on Trakt.", symbol: "exclamationmark.triangle", needsAttention: true, isWorking: false, action: .check)
        }
        if diagnostics.changes.contains(where: { $0.state == .confirming }) || diagnostics.failure == .confirmation {
            return Self(title: "Waiting for Confirmation", detail: confirmationSummary(count: diagnostics.changes.filter { $0.state == .confirming }.count), symbol: "clock.badge.exclamationmark", needsAttention: true, isWorking: false, action: .check)
        }
        if diagnostics.deadletterOperationCount > 0 || error != nil || diagnostics.lastErrorDescription != nil {
            return Self(title: "Sync Needs Attention", detail: "Review pending changes or try again.", symbol: "exclamationmark.triangle", needsAttention: true, isWorking: false,
                        action: diagnostics.changes.contains { $0.state == .failed && $0.isOnThisDevice } ? .retry : .sync)
        }
        if diagnostics.duplicateCandidateCount > 0 {
            return Self(title: "Library Check Recommended", detail: "Open Help with Sync to check local library data.", symbol: "exclamationmark.triangle", needsAttention: true, isWorking: false, action: .sync)
        }
        if diagnostics.hasPendingWork {
            return Self(title: "Changes Pending", detail: "Saved changes are waiting to upload.", symbol: "clock", needsAttention: false, isWorking: false, action: .sync)
        }
        return Self(title: diagnostics.initialBaselineComplete ? "Sync Complete" : "Ready to Sync",
                    detail: "Changes sync automatically.", symbol: "checkmark.circle", needsAttention: false, isWorking: false, action: .sync)
    }

    static func confirmationSummary(count: Int) -> String {
        count == 1 ? "1 watched change needs checking." : count > 1
            ? "\(count) watched changes need checking." : "A watched change needs checking."
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
        isSyncing || isMaintainingSync || isErasingAllData || traktIsConnecting || isReadOnlyPreview
    }
}

/// Keep status and its action together; stack the accessory at accessibility sizes.
struct SettingsStatusRow<Accessory: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    let detail: String
    let symbol: String
    var needsAttention = false
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    copy
                    accessory()
                }
            } else {
                HStack(spacing: AppSpacing.medium) {
                    copy
                    Spacer(minLength: 8)
                    accessory()
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var copy: some View {
        Group {
            if typeSize.isAccessibilitySize {
                statusCopy
            } else {
                Label {
                    statusCopy
                } icon: {
                    Image(systemName: symbol)
                        .foregroundStyle(needsAttention ? Color.orange : Color.accentColor)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusCopy: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text(title).foregroundStyle(.primary)
            if !detail.isEmpty {
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
    }

}

struct SyncDateRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    let date: Date

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(title)
                Text(date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            LabeledContent(title, value: date.formatted(date: .abbreviated, time: .shortened))
        }
    }
}
