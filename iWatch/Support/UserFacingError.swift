import Foundation

/// Map typed failures to safe copy. Provider response bodies stay out of ordinary UI.
nonisolated enum UserFacingError {
    enum Context { case library, search, details, action }

    static func message(for error: Error, context: Context = .details) -> String {
        if let network = error as? URLError {
            switch network.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
                return "Check your connection, then try again."
            case .timedOut: return "The request timed out. Try again in a moment."
            default: break
            }
        }
        if let appError = error as? AppError {
            switch appError {
            case .network: return "Check your connection, then try again."
            case .rateLimited: return "The service is busy. Wait a moment before trying again."
            case let .httpStatus(code, _) where code == 429:
                return "The service is busy. Wait a moment before trying again."
            case .httpStatus, .decoding:
                return "This information is temporarily unavailable. Try again later."
            default: break
            }
        }
        switch context {
        case .library: return "Your library couldn’t be refreshed. Try again."
        case .search: return "Search couldn’t finish. Try again."
        case .details: return "This information couldn’t be loaded. Try again."
        case .action: return "Your change couldn’t be saved. Try again."
        }
    }
}
