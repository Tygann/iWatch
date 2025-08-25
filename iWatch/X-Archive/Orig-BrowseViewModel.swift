//import Foundation
//internal import Combine
//
//@MainActor
//final class BrowseViewModel: ObservableObject {
//    @Published var trendingMovies: [SimpleDTO] = []
//    @Published var trendingTV: [SimpleDTO] = []
//    @Published var isLoading = false
//    @Published var error: String?
//
//    private let repo: ContentRepository
//    private let api: ContentAPI
//
//    init(repo: ContentRepository, api: ContentAPI) {
//        self.repo = repo
//        self.api = api
//    }
//
//    func load() async {
//        isLoading = true
//        error = nil
//        async let m = api.trendingMovies(page: 1)
//        async let t = api.trendingTV(page: 1)
//        do {
//            let (mm, tt) = try await (m, t)
//            trendingMovies = mm.map(\.simple)
//            trendingTV = tt.map(\.simple)
//            isLoading = false
//        } catch {
//            isLoading = false
//            self.error = "Failed to load trending content."
//        }
//    }
//
//    func addToWatchlist(_ item: SimpleDTO, kind: MediaItem.Kind) {
//        repo.addToWatchlist(simple: item, kind: kind)
//    }
//}
