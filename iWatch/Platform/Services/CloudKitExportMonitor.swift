import CloudKit
import CoreData
import Foundation

enum CloudExportConfirmation: Sendable, Equatable {
    case completed(Date)
    case unavailable(String)
    case failed(String)
    case timedOut
}

@MainActor
protocol CloudExportMonitoring: AnyObject {
    func waitForExport(startingAfter date: Date, timeout: Duration) async -> CloudExportConfirmation
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
    private var recentEvents: [ExportEvent] = []
    private var waiters: [UUID: Waiter] = [:]

    init(containerIdentifier: String) {
        self.container = CKContainer(identifier: containerIdentifier)
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
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func waitForExport(startingAfter date: Date, timeout: Duration) async -> CloudExportConfirmation {
        let accountStatus: CKAccountStatus
        do {
            accountStatus = try await container.accountStatus()
        } catch {
            return .unavailable(error.localizedDescription)
        }

        guard accountStatus == .available else {
            return .unavailable(Self.accountMessage(for: accountStatus))
        }

        if let event = recentEvents.first(where: { $0.startDate >= date }) {
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
                as? NSPersistentCloudKitContainer.Event,
              event.type == .export,
              let endDate = event.endDate else {
            return
        }

        let export = ExportEvent(
            startDate: event.startDate,
            endDate: endDate,
            succeeded: event.succeeded,
            errorDescription: event.error?.localizedDescription
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
