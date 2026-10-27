import Foundation
import Observation

/// No repositories, account sync, or notification scheduling exist until opening succeeds.
@MainActor @Observable
final class AppStartupController {
    typealias Factory = @MainActor () async throws -> AppContainer
    private let factory: Factory
    private(set) var container: AppContainer?
    private(set) var issue: StoreOpeningIssue?
    private(set) var isOpening = false

    init(factory: @escaping Factory = { try await AppContainer.bootstrap() }) {
        self.factory = factory
    }

    func open() async {
        guard container == nil, !isOpening else { return }
        isOpening = true
        issue = nil
        defer { isOpening = false }
        do {
            container = try await factory()
        } catch {
            // Keep only safe presentation data; never display store paths or record contents.
            issue = StoreOpeningIssue(error: error)
        }
    }
}

nonisolated struct StoreOpeningIssue: Equatable {
    enum Kind { case storageFull, accessUnavailable, unavailable }
    let kind: Kind
    let reference: String

    init(error: Error) {
        var current = error as NSError
        var detected: Kind = .unavailable
        var code = current.code
        // Inspect typed underlying errors, not localized/provider message strings.
        for _ in 0..<8 {
            if current.domain == NSCocoaErrorDomain && current.code == CocoaError.fileWriteOutOfSpace.rawValue
                || current.domain == NSPOSIXErrorDomain && current.code == 28 {
                detected = .storageFull
                code = current.code
                break
            }
            if current.domain == NSCocoaErrorDomain && current.code == CocoaError.fileReadNoPermission.rawValue {
                detected = .accessUnavailable
                code = current.code
            }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
            current = underlying
        }
        kind = detected
        reference = "Library opening (\(code))"
    }

    var message: String {
        switch kind {
        case .storageFull: "Free up some device storage, then try again."
        case .accessUnavailable: "Your library isn’t accessible right now. Unlock your device and try again."
        case .unavailable: "Your library couldn’t be opened. Try again, or contact support if this continues."
        }
    }
}
