import SwiftUI
import SwiftData

struct ShowsView: View {
    @Environment(\.modelContext) private var context

    @State private var showSettings = false
    @State private var detailRef: MediaRef? = nil        // sheet selection

    @Query(
        filter: #Predicate<ProgressItem> { $0.isInWatchlist && $0.media.kindRaw == "tv" },
        sort: [SortDescriptor(\ProgressItem.media.title, order: .forward)]
    )
    private var tvFollowing: [ProgressItem]

    @Query(
        filter: #Predicate<ProgressItem> { $0.isInWatchlist && $0.hasUnwatched && $0.media.kindRaw == "tv" },
        sort: [SortDescriptor(\ProgressItem.media.title, order: .forward)]
    )
    private var tvNeedingWatch: [ProgressItem]

    enum Segment: String, CaseIterable, Identifiable {
        case following = "Following"
        case toWatch   = "To Watch"
        var id: String { rawValue }
    }
    @State private var segment: Segment = .following

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        NavigationStack {
            VStack {
                let items = segment == .following ? tvFollowing : tvNeedingWatch

                if items.isEmpty {
                    ContentUnavailableView(
                        segment == .following ? "No tracked shows yet" : "Nothing to watch",
                        systemImage: "tv",
                        description: Text(segment == .following
                                          ? "Add TV shows from Search to start tracking."
                                          : "You’re all caught up on the shows you follow.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(items) { p in
                                let ref = MediaRef(id: p.media.remoteID, kind: .tv)

                                MediaTile(
                                    ref: ref,
                                    title: p.media.title,
                                    posterPath: p.media.posterPath,
                                    showTitle: true,
                                    selectedRef: $detailRef
                                ) {
                                    // Extra menu for this screen
                                    if p.hasUnwatched {
                                        Button("Mark Caught Up") {
                                            p.hasUnwatched = false
                                            try? context.save()
                                        }
                                    } else {
                                        Button("Mark Needs Watching") {
                                            p.hasUnwatched = true
                                            try? context.save()
                                        }
                                    }
                                }
                                .frame(width: 110)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                    }
                }
            }
            .navigationTitle("Shows")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: {
                        Image(systemName: "person.crop.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.primary, .clear)
                            .scaleEffect(1.5)
                    }
                }
            }
            .safeAreaBar(edge: .top) {
                Picker("", selection: $segment) {
                    ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button(role: .close) { showSettings = false }
                            }
                        }
                }
            }
            // Single presenter for MediaDetailView as a sheet
            .sheet(item: $detailRef) { ref in
                NavigationStack {
                    MediaDetailView(ref: ref)
                        .presentationDragIndicator(.visible)
//                        .presentationDetents([.medium, .large])
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(role: .close) { detailRef = nil }
                            }
                        }
                }
            }
        }
    }
}







//import SwiftUI
//import SwiftData
//
//struct ShowsView: View {
//    @Environment(\.modelContext) private var context
//    
//    @State private var selected: ProgressItem?
//    @State private var showDetail = false
//    @State private var showSettings = false
//    @State private var detailRef: MediaRef? = nil
//    
//    @Query(
//        filter: #Predicate<ProgressItem> { $0.isInWatchlist && $0.media.kindRaw == "tv" },
//        sort: [SortDescriptor(\ProgressItem.media.title, order: .forward)]
//    )
//    private var tvFollowing: [ProgressItem]
//
//    @Query(
//        filter: #Predicate<ProgressItem> { $0.isInWatchlist && $0.hasUnwatched && $0.media.kindRaw == "tv" },
//        sort: [SortDescriptor(\ProgressItem.media.title, order: .forward)]
//    )
//    private var tvNeedingWatch: [ProgressItem]
//
//    enum Segment: String, CaseIterable, Identifiable { case following = "Following", toWatch = "To Watch"; var id: String { rawValue } }
//    @State private var segment: Segment = .following
//
//    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 12)]
//
//    var body: some View {
//        NavigationStack {
//            VStack {
//                let items = segment == .following ? tvFollowing : tvNeedingWatch
//
//                if items.isEmpty {
//                    ContentUnavailableView(
//                        segment == .following ? "No tracked shows yet" : "Nothing to watch",
//                        systemImage: "tv",
//                        description: Text(segment == .following
//                                          ? "Add TV shows from Discover to start tracking."
//                                          : "You’re all caught up on the shows you follow.")
//                    )
//                    .frame(maxWidth: .infinity, maxHeight: .infinity)
//                } else {
//                    ScrollView {
//                        LazyVGrid(columns: cols, spacing: 12) {
//                            ForEach(items) { show in
//                                Button {
//                                    selected = show
//                                    showDetail = true
//                                } label: {
////                                    VStack(spacing: 6) {
////                                    ZStack(alignment: .topTrailing) {
//                                        PosterImage(path: show.media.posterPath)
//                                            .frame(width: 110, height: 165)
//                                            .clipShape(RoundedRectangle(cornerRadius: 12))
//                                            .clipped()
//                                        
////                                        if p.hasUnwatched {
////                                            Circle().frame(width: 10, height: 10).padding(6)
////                                        }
////                                    }
//                                        
//                                        
////                                        Text(show.media.title)
////                                            .font(.caption)
////                                            .lineLimit(2)
////                                            .frame(width: 110, alignment: .leading)
////                                    }
//                                }
//                                .contentShape(Rectangle())
////                                .onTapGesture { selected = show }
//                                .contextMenu {
//                                    Button("Mark Caught Up") { show.hasUnwatched = false; try? context.save() }
//                                    Button("Mark Needs Watching") { show.hasUnwatched = true; try? context.save() }
//                                }
//                            }
//                        }
//                        .padding(.horizontal, 12)
//                        .padding(.top, 12)
//                    }
//                }
//            }
//            .navigationTitle("Shows")
//            .toolbarTitleDisplayMode(.inlineLarge)
//            .toolbar {
//                // Settings Button
//                ToolbarItem(placement: .primaryAction) {
//                    Button(action: {
//                        showSettings = true
//                    }) {
//                        Image(systemName: "person.crop.circle.fill")
//                            .symbolRenderingMode(.palette)
//                            .foregroundStyle(.primary, .clear)
//                            .scaleEffect(1.5)
//                    }
//                }
//            }
//            .safeAreaBar(edge: .top) {
//                Picker("", selection: $segment) {
//                    ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
//                }
//                .pickerStyle(.segmented)
//                .padding(.horizontal)
//            }
//            .sheet(isPresented: $showSettings) {
//                NavigationStack {
//                    // Settings View
//                    SettingsView()
//                        .toolbar {
//                            ToolbarItem(placement: .primaryAction) {
//                                // Close Button
//                                Button(role: .close) {
//                                    showSettings = false
//                                }
//                            }
//                        }
//                }
//            }
//            .sheet(item: $detailRef) { ref in
//                NavigationStack {
//                    MediaDetailView(ref: ref)
//                        .presentationDragIndicator(.visible)
//                        .presentationDetents([.medium, .large])   // tweak to taste
//                        .toolbar {
//                            ToolbarItem(placement: .topBarTrailing) {
//                                Button(role: .close) { detailRef = nil }
//                            }
//                        }
//                }
//            }
////            .sheet(isPresented: $showDetail) {
////                if let selected = selected {
////                    NavigationStack {
//////                        ShowDetailView(progress: selected)
////                        MediaDetailView(ref: .init(id: selected.media.remoteID, kind: .tv))
////                            .presentationBackground(.clear)
////                            .presentationDragIndicator(.visible)
////                            .toolbar {
////                                // Close Button
////                                ToolbarItem(placement: .topBarTrailing) {
////                                    Button(role: .close) {
////                                        showDetail = false
////                                    }
////                                }
////                            }
////                    }
////                }
////            }
//        }
//    }
//}
