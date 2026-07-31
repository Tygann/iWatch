import Foundation

enum DataResetReceiptStore {
    private static let pendingResetKey = "dataReset.pendingCloudExportAt"

    static var pendingResetAt: Date? {
        UserDefaults.standard.object(forKey: pendingResetKey) as? Date
    }

    static func markPending(at date: Date) {
        UserDefaults.standard.set(date, forKey: pendingResetKey)
    }

    static func markConfirmed() {
        UserDefaults.standard.removeObject(forKey: pendingResetKey)
    }
}
