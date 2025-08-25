//import SwiftUI
//
//struct SearchView: View {
//    @StateObject var vm: SearchViewModel
//
//    var body: some View {
//        NavigationStack {
//            VStack {
//                TextField("Search movies, TV…", text: $vm.query)
//                    .textFieldStyle(.roundedBorder)
//                    .padding(.horizontal)
//                    .onSubmit { vm.beginSearch() }
//                    .onChange(of: vm.query) { _, _ in
//                        // Lightweight debounce
//                        Task { try? await Task.sleep(nanoseconds: 400_000_000); await MainActor.run { vm.beginSearch() } }
//                    }
//
//                if vm.isSearching {
//                    LoadingView()
//                } else if vm.results.isEmpty, !vm.query.isEmpty {
//                    ContentUnavailableView.search
//                } else {
//                    PosterGrid(items: vm.results, imageURL: { $0.posterURL }, title: { $0.title }) { _ in }
//                }
//            }
//            .navigationTitle("Search")
//        }
//    }
//}
