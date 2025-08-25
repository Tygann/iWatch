//import Foundation
//internal import Combine
//
//@MainActor
//final class SearchViewModel: ObservableObject {
//    @Published var query: String = ""
//    @Published var results: [SimpleDTO] = []
//    @Published var isSearching = false
//
//    private let api: ContentAPI
//    private var searchTask: Task<Void, Never>?
//
//    init(api: ContentAPI) {
//        self.api = api
//    }
//
//    func beginSearch() {
//        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
//        guard !q.isEmpty else {
//            results = []
//            return
//        }
//        searchTask?.cancel()
//        searchTask = Task { [weak self] in
//            await self?.performSearch(query: q)
//        }
//    }
//
//    private func performSearch(query: String) async {
//        isSearching = true
//        defer { isSearching = false }
//        do {
//            let res = try await api.search(query: query, page: 1)
//            results = res.compactMap { $0.simple }
//        } catch {
//            results = []
//        }
//    }
//}
