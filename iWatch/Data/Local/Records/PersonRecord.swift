import Foundation
import SwiftData

@Model
final class SyncStateRecord {
    // CloudKit-backed SwiftData cannot enforce unique constraints, so repositories
    // treat this as the logical identity for manual upserts and dedupe.
    var accountKey: String = ""
    var generationID: String = ""

    var initialBaselineComplete: Bool = false
    var lastSuccessfulPullAt: Date?
    var lastSuccessfulPushAt: Date?
    var lastSeenRemoteActivityAt: Date?

    init(accountKey: String,
         initialBaselineComplete: Bool = false,
         lastSuccessfulPullAt: Date? = nil,
         lastSuccessfulPushAt: Date? = nil,
         lastSeenRemoteActivityAt: Date? = nil,
         generationID: String = "") {
        self.accountKey = accountKey
        self.initialBaselineComplete = initialBaselineComplete
        self.lastSuccessfulPullAt = lastSuccessfulPullAt
        self.lastSuccessfulPushAt = lastSuccessfulPushAt
        self.lastSeenRemoteActivityAt = lastSeenRemoteActivityAt
        self.generationID = generationID
    }
}
