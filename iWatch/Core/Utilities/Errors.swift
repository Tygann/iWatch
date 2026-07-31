import Foundation

enum AppError: LocalizedError {
    case network(String)
    case httpStatus(code: Int, message: String?)
    case decoding(Error)
    case featureNotImplemented(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .network(let m): return m
        case .httpStatus(let code, let msg): return "HTTP \(code): \(msg ?? "Unknown")"
        case .decoding(let e): return "Decoding error: \(e.localizedDescription)"
        case .featureNotImplemented(let what): return "Not implemented: \(what)"
        case .unknown(let m): return m
        }
    }
}

/// Common helpers for NSError bridging
extension Error {
    var isCancelled: Bool {
        let nsErr = self as NSError
        return nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled
    }
}
