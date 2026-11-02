import Foundation

/// Disposable first-frame data. SwiftData remains the source of truth.
@MainActor
final class LibraryPreviewStore {
    struct Scope: Codable, Equatable {
        let generation: String
        let accountKey: String?
    }

    private struct Entry<Value: Codable>: Codable {
        let version: Int
        let scope: Scope
        let savedAt: Date
        let value: Value
    }

    private let directory: URL
    private let maximumAge: TimeInterval = 7 * 86400
    private let maximumBytes = 4 * 1024 * 1024

    init(directory: URL) {
        self.directory = directory
    }

    static func live() -> LibraryPreviewStore {
        LibraryPreviewStore(directory: URL.cachesDirectory.appending(path: "LibraryPreviews", directoryHint: .isDirectory))
    }

    func movies(scope: Scope, now: Date = .now) -> [LibraryMovieItem]? {
        read("movies", scope: scope, now: now)
    }

    func shows(scope: Scope, now: Date = .now) -> [LibraryShowItem]? {
        read("shows", scope: scope, now: now)
    }

    func saveMovies(_ items: [LibraryMovieItem], scope: Scope, now: Date = .now) {
        write(items, name: "movies", scope: scope, now: now)
    }

    func saveShows(_ items: [LibraryShowItem], scope: Scope, now: Date = .now) {
        write(items, name: "shows", scope: scope, now: now)
    }

    func clear() {
        for name in ["movies", "shows"] {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name + ".json"))
        }
    }

    private func read<Value: Codable>(_ name: String, scope: Scope, now: Date) -> Value? {
        let url = directory.appendingPathComponent(name + ".json")
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? maximumBytes + 1
            guard size <= maximumBytes else { throw CocoaError(.fileReadCorruptFile) }
            let entry = try JSONDecoder().decode(Entry<Value>.self, from: Data(contentsOf: url))
            guard entry.version == 1, entry.scope == scope,
                  entry.savedAt <= now, now.timeIntervalSince(entry.savedAt) < maximumAge else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return entry.value
        } catch {
            // Missing, expired, or incompatible previews simply fall back to the database.
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    private func write<Value: Codable>(_ value: Value, name: String, scope: Scope, now: Date) {
        let url = directory.appendingPathComponent(name + ".json")
        do {
            let data = try JSONEncoder().encode(Entry(version: 1, scope: scope, savedAt: now, value: value))
            guard data.count <= maximumBytes else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            // Preview writes must never turn a successful library read into a failure.
        }
    }
}
