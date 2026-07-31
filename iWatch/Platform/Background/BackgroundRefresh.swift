import BackgroundTasks
import Foundation

enum BackgroundRefresh {
    static let appRefreshIdentifier = "com.tyler.iWatch.sync.refresh"
    static let foregroundStalenessInterval: TimeInterval = 10 * 60
    static let earliestAppRefreshInterval: TimeInterval = 15 * 60

    static var isAvailableInCurrentProcess: Bool {
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments

        if environment["XCTestConfigurationFilePath"] != nil { return false }
        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return false }
        if arguments.contains("UITEST_MODE") { return false }
        return true
    }

    static func scheduleAppRefresh(after interval: TimeInterval = earliestAppRefreshInterval) {
        guard isAvailableInCurrentProcess else { return }

        let scheduler = BGTaskScheduler.shared
        scheduler.cancel(taskRequestWithIdentifier: appRefreshIdentifier)

        let request = BGAppRefreshTaskRequest(identifier: appRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)

        do {
            try scheduler.submit(request)
        } catch {
            #if DEBUG
            print("[BackgroundRefresh] Failed to schedule app refresh:", error)
            #endif
        }
    }

    static func cancelScheduledRefresh() {
        guard isAvailableInCurrentProcess else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: appRefreshIdentifier)
    }
}
