import CloudKit
import CoreData
import Foundation

// MARK: - Export State

enum CloudExportConfirmation: Sendable, Equatable {
    case completed(Date)
    case unavailable(String)
    case failed(String)
    case timedOut
}

enum CloudStoreActivity: Sendable {
    case accountChanged
    case importing
    case imported(Date)
    case exporting
    case exported(Date)
    case failed(String)
}

// MARK: - CloudKit Export Monitor

@MainActor
protocol CloudExportMonitoring: AnyObject {
    func waitForExport(startingAfter date: Date, timeout: Duration) async -> CloudExportConfirmation
    func observeActivity(_ handler: @escaping @MainActor (CloudStoreActivity) -> Void)
}

extension CloudExportMonitoring {
    func observeActivity(_ handler: @escaping @MainActor (CloudStoreActivity) -> Void) {}
}

@MainActor
final class CloudKitExportMonitor: CloudExportMonitoring {
    private struct ExportEvent {
        let startDate: Date
        let endDate: Date
        let succeeded: Bool
        let errorDescription: String?
    }

    private struct Waiter {
        let startingAfter: Date
        let continuation: CheckedContinuation<CloudExportConfirmation, Never>
    }

    private let container: CKContainer
    private var observer: NSObjectProtocol?
    private var accountObserver: NSObjectProtocol?
    private var activityHandler: (@MainActor (CloudStoreActivity) -> Void)?
    private var recentEvents: [ExportEvent] = []
    private var waiters: [UUID: Waiter] = [:]

    init(containerIdentifier: String) {
        self.container = CKContainer(identifier: containerIdentifier)
        accountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.activityHandler?(.accountChanged) }
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.record(notification)
            }
        }
    }

    deinit {
        if let accountObserver { NotificationCenter.default.removeObserver(accountObserver) }
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func observeActivity(_ handler: @escaping @MainActor (CloudStoreActivity) -> Void) {
        activityHandler = handler
    }

    func waitForExport(startingAfter date: Date, timeout: Duration) async -> CloudExportConfirmation {
        let accountStatus: CKAccountStatus
        do {
            accountStatus = try await container.accountStatus()
        } catch {
            return .unavailable(Self.errorSummary(error))
        }

        guard accountStatus == .available else {
            return .unavailable(Self.accountMessage(for: accountStatus))
        }

        if let event = recentEvents.last(where: { $0.startDate >= date }) {
            return confirmation(for: event)
        }

        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters[waiterID] = Waiter(startingAfter: date, continuation: continuation)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: timeout)
                    self?.finishWaiter(waiterID, with: .timedOut)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishWaiter(waiterID, with: .timedOut)
            }
        }
    }

    private func record(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
        guard event.type == .import || event.type == .export else { return }
        guard let endDate = event.endDate else {
            activityHandler?(event.type == .import ? .importing : .exporting)
            return
        }
        if event.succeeded {
            activityHandler?(event.type == .import ? .imported(endDate) : .exported(endDate))
        } else {
            activityHandler?(.failed(Self.errorSummary(event.error)))
        }
        guard event.type == .export else { return }

        let export = ExportEvent(
            startDate: event.startDate,
            endDate: endDate,
            succeeded: event.succeeded,
            errorDescription: event.succeeded ? nil : Self.errorSummary(event.error)
        )
        recentEvents.append(export)
        recentEvents = Array(recentEvents.suffix(20))

        for (id, waiter) in waiters where export.startDate >= waiter.startingAfter {
            finishWaiter(id, with: confirmation(for: export))
        }
    }

    private func finishWaiter(_ id: UUID, with result: CloudExportConfirmation) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume(returning: result)
    }

    private func confirmation(for event: ExportEvent) -> CloudExportConfirmation {
        if event.succeeded {
            return .completed(event.endDate)
        }
        return .failed(event.errorDescription ?? "iCloud couldn’t finish updating your data.")
    }

    static func errorSummary(_ error: Error?, depth: Int = 0) -> String {
        guard let error, depth < 4 else { return "iCloud couldn’t finish updating your data." }
        let nsError = error as NSError
        if let partial = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error], !partial.isEmpty {
            return Set(partial.values.map { errorSummary($0, depth: depth + 1) }).sorted().joined(separator: " ")
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return errorSummary(underlying, depth: depth + 1)
        }
        // Never include record IDs, payloads, server descriptions, or userInfo.
        if let cloud = error as? CKError {
            switch cloud.code {
            case .networkUnavailable, .networkFailure: return "iCloud is waiting for a network connection."
            case .notAuthenticated: return "Sign in to iCloud in Settings, then reopen iWatch."
            case .quotaExceeded: return "Your iCloud storage is full. Free some space and try again."
            case .serverRejectedRequest, .invalidArguments, .unknownItem:
                return "iCloud couldn’t accept the library update. Check that the app’s cloud schema is up to date."
            case .serviceUnavailable, .requestRateLimited, .zoneBusy:
                return "iCloud is temporarily busy and will retry."
            default: return "iCloud update failed (code \(cloud.code.rawValue)). Try again later."
            }
        }
        return "iCloud couldn’t finish updating your data. Try again later."
    }

    private static func accountMessage(for status: CKAccountStatus) -> String {
        switch status {
        case .available:
            return "iCloud is available."
        case .noAccount:
            return "Sign in to iCloud in Settings to remove this data from iCloud."
        case .restricted:
            return "iCloud access is restricted on this device."
        case .couldNotDetermine:
            return "iCloud account status couldn’t be determined."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable. Keep iWatch installed and try again later."
        @unknown default:
            return "iCloud is currently unavailable."
        }
    }
}

// MARK: - Immediate Export Monitor

@MainActor
final class ImmediateCloudExportMonitor: CloudExportMonitoring {
    private let result: CloudExportConfirmation

    init(result: CloudExportConfirmation = .completed(.now)) {
        self.result = result
    }

    func waitForExport(startingAfter: Date, timeout: Duration) async -> CloudExportConfirmation {
        result
    }
}
