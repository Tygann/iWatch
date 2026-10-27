import Foundation
import SwiftData
import Testing
@testable import iWatch

@Suite @MainActor
struct StartupRecoveryTests {
    @Test
    func failedOpenKeepsServicesUnavailableAndRetryCanSucceed() async {
        let attempts = TestValue(0)
        let startup = AppStartupController(factory: {
            attempts.value += 1
            if attempts.value == 1 { throw CocoaError(.fileWriteOutOfSpace) }
            return AppContainer.preview(seedCatalog: false)
        })
        await startup.open()
        #expect(startup.container == nil)
        #expect(startup.issue?.kind == .storageFull)
        #expect(!startup.isOpening)
        await startup.open()
        #expect(startup.container != nil)
        #expect(startup.issue == nil)
        await startup.open()
        #expect(attempts.value == 2)
    }

    @Test
    func concurrentRetriesOpenOnlyOneContainer() async {
        let attempts = TestValue(0)
        let startup = AppStartupController(factory: {
            attempts.value += 1
            try await Task.sleep(for: .milliseconds(50))
            return AppContainer.preview(seedCatalog: false)
        })
        let first = Task { await startup.open() }
        await Task.yield()
        await startup.open()
        await first.value
        #expect(attempts.value == 1)
        #expect(startup.container != nil)
    }

    @Test
    func openingIssueUsesTypedCausesAndHidesPrivateDetails() {
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: 28,
            userInfo: [NSLocalizedDescriptionKey: "private-path-and-record-content"])
        let error = NSError(domain: "PrivateAccountName", code: 1,
            userInfo: [NSUnderlyingErrorKey: underlying])
        let issue = StoreOpeningIssue(error: error)
        #expect(issue.kind == .storageFull)
        #expect(!issue.message.contains("private"))
        #expect(!issue.reference.contains("PrivateAccountName"))
    }

    @Test
    func invalidExistingStoreIsNotReplacedOnFailedOpen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.store")
        let original = Data("This is deliberately not a SQLite database.".utf8)
        try original.write(to: url)
        #expect(throws: (any Error).self) {
            _ = try Persistence(storeURL: url, cloudKitDatabase: ModelConfiguration.CloudKitDatabase.none)
        }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test
    func reopeningTheSameStorePreservesLibraryAndAccountBoundOutbox() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.store")
        do {
            let persistence = try Persistence(storeURL: url, cloudKitDatabase: ModelConfiguration.CloudKitDatabase.none)
            let context = persistence.makeContext()
            context.insert(WatchedEventRecord(kind: .movie, tmdbID: 42, watchedAt: .now))
            context.insert(SyncOperationRecord(kind: .addHistory, payload: Data(), accountKey: "account-a"))
            try context.save()
        }
        let reopened = try Persistence(storeURL: url, cloudKitDatabase: ModelConfiguration.CloudKitDatabase.none)
        let context = reopened.makeContext()
        #expect(try context.fetchCount(FetchDescriptor<WatchedEventRecord>()) == 1)
        #expect(try context.fetch(FetchDescriptor<SyncOperationRecord>()).first?.accountKey == "account-a")
    }
}
