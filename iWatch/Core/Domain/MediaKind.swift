import Foundation

nonisolated enum MediaKind: String, Codable, Sendable, CaseIterable {
    case movie
    case show
    case episode
    case person
}
