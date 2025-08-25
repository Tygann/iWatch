//import SwiftUI
//import SwiftData
//
//struct WatchlistView: View {
//    @Environment(\.modelContext) private var context
//
//    @Query(
//        filter: #Predicate<ProgressItem> { $0.isInWatchlist },
//        sort: [SortDescriptor(\ProgressItem.media.dateAdded, order: .reverse)]
//    )
//    private var progressItems: [ProgressItem]
//
//    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 12)]
//
//    var body: some View {
//        NavigationStack {
//            if progressItems.isEmpty {
//                ContentUnavailableView(
//                    "Nothing saved yet",
//                    systemImage: "bookmark",
//                    description: Text("Add movies and shows from Discover.")
//                )
//            } else {
//                ScrollView {
//                    LazyVGrid(columns: cols, spacing: 12) {
//                        ForEach(progressItems) { p in
//                            VStack(spacing: 6) {
//                                PosterImage(path: p.media.posterPath)
//                                    .frame(width: 110, height: 165)
//                                    .clipShape(RoundedRectangle(cornerRadius: 12))
//                                    .clipped()
//
//                                Text(p.media.title)
//                                    .font(.caption)
//                                    .lineLimit(2)
//                                    .frame(width: 110, alignment: .leading)
//                            }
//                            .contentShape(Rectangle())
//                            // (Optional) actions:
//                            .contextMenu {
//                                Button("Remove from Watchlist") {
//                                    p.isInWatchlist = false
//                                    try? context.save()
//                                }
//                            }
//                        }
//                    }
//                    .padding(.horizontal, 12)
//                    .padding(.top, 12)
//                }
//                .navigationTitle("Watchlist")
//            }
//        }
//    }
//}
