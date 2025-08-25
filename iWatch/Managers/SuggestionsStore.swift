import Foundation
import SwiftData
import Combine

@MainActor
final class SuggestionsStore: ObservableObject {
    @Published var suggested: [SimpleDTO] = []
    @Published var isLoading = false
    @Published var errorText: String?

    private let env: AppEnvironment
    private let modelContext: ModelContext

    init(env: AppEnvironment, modelContext: ModelContext) {
        self.env = env
        self.modelContext = modelContext
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            async let moviesTask = env.contentAPI.trendingMovies(page: 1)
            async let showsTask  = env.contentAPI.trendingTV(page: 1)
            let (movies, shows) = try await (moviesTask, showsTask)
            let combined = movies + shows

            // If you later store genre prefs locally, fill this set.
            let userGenres: Set<Int> = collectUserGenreIDs()

            let ranked: [SimpleDTO]
            if !userGenres.isEmpty {
                ranked = combined.sorted {
                    overlapScore($0.genreIDs, userGenres) > overlapScore($1.genreIDs, userGenres)
                }
            } else {
                // balanced fallback
                ranked = interleave(movies, shows)
            }

            suggested = dedupeByKindAndID(ranked, limit: 20)
        } catch {
            errorText = "Couldn’t load suggestions. Pull to refresh."
            #if DEBUG
            print("Suggestions refresh error:", error)
            #endif
        }
    }

    // MARK: - Prefs (stub for now; safe to return empty)
    private func collectUserGenreIDs() -> Set<Int> {
        // Later: harvest from persisted MediaItem/Watchlist if you add genreIDs there.
        return []
    }

    private func overlapScore(_ a: [Int]?, _ prefs: Set<Int>) -> Int {
        guard let a else { return 0 }
        return a.reduce(into: 0) { score, g in if prefs.contains(g) { score += 1 } }
    }

    // MARK: - Helpers
    private func interleave<T>(_ a: [T], _ b: [T]) -> [T] {
        var out: [T] = []; out.reserveCapacity(a.count + b.count)
        let n = max(a.count, b.count)
        for i in 0..<n {
            if i < a.count { out.append(a[i]) }
            if i < b.count { out.append(b[i]) }
        }
        return out
    }

    private func dedupeByKindAndID(_ items: [SimpleDTO], limit: Int) -> [SimpleDTO] {
        var seen = Set<String>(), out: [SimpleDTO] = []; out.reserveCapacity(limit)
        for it in items {
            if seen.insert("\(it.kind)#\(it.id)").inserted {
                out.append(it)
                if out.count == limit { break }
            }
        }
        return out
    }
}
