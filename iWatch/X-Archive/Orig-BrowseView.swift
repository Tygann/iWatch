//import SwiftUI
//
//struct BrowseView: View {
//    @StateObject var vm: BrowseViewModel
//
//    var body: some View {
//        NavigationStack {
//            Group {
//                if vm.isLoading {
//                    LoadingView()
//                } else if let error = vm.error {
//                    ErrorView(message: error)
//                } else {
//                    List {
//                        Section("Trending Movies") {
//                            PosterGrid(items: vm.trendingMovies, imageURL: { $0.posterURL }, title: { $0.title }) { item in
//                                vm.addToWatchlist(item, kind: .movie)
//                            }
//                            .listRowInsets(EdgeInsets())
//                        }
//                        Section("Trending TV") {
//                            PosterGrid(items: vm.trendingTV, imageURL: { $0.posterURL }, title: { $0.title }) { item in
//                                vm.addToWatchlist(item, kind: .tv)
//                            }
//                            .listRowInsets(EdgeInsets())
//                        }
//                    }
//                }
//            }
//            .navigationTitle("Discover")
//            .task { await vm.load() }
//        }
//    }
//}
