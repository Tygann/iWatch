// iWatch/Features/Movies/MoviesView.swift
import SwiftUI
import SwiftData

struct MoviesView: View {
    @Environment(\.modelContext) private var context
    @State private var showSettings = false
    @State private var detailRef: MediaRef? = nil

    // All tracked Movies
    @Query(
        filter: #Predicate<ProgressItem> { $0.isInWatchlist && $0.media.kindRaw == "movie" },
        sort: [SortDescriptor(\ProgressItem.media.title, order: .forward)]
    )
    private var moviesFollowing: [ProgressItem]

    // Tracked Movies you still need to watch
    @Query(
        filter: #Predicate<ProgressItem> { $0.isInWatchlist && !$0.watched && $0.media.kindRaw == "movie" },
        sort: [SortDescriptor(\ProgressItem.media.title, order: .forward)]
    )
    private var moviesToWatch: [ProgressItem]

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
                let items = segment == .following ? moviesFollowing : moviesToWatch

                if items.isEmpty {
                    ContentUnavailableView(
                        segment == .following ? "No tracked movies yet" : "Nothing to watch",
                        systemImage: "film",
                        description: Text(segment == .following
                                          ? "Add movies from Search to start tracking."
                                          : "You’re all caught up on the movies you follow.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(items) { p in
                                let ref = MediaRef(id: p.media.remoteID, kind: .movie)

                                MediaTile(
                                    ref: ref,
                                    title: p.media.title,
                                    posterPath: p.media.posterPath,
                                    showTitle: true,
                                    selectedRef: $detailRef
                                ) {
                                    // Extra context‑menu actions specific to this screen
                                    if p.watched {
                                        Button("Mark Unwatched") {
                                            p.watched = false
                                            try? context.save()
                                        }
                                    } else {
                                        Button("Mark Watched") {
                                            p.watched = true
                                            try? context.save()
                                        }
                                    }
                                }
                                .frame(width: 110) // keeps grid cell width
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                    }
                }
            }
            .navigationTitle("Movies")
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
            // Detail sheet presenter
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






//// iWatch/Features/Movies/MoviesView.swift
//import SwiftUI
//import SwiftData
//
//struct MoviesView: View {
//    @Environment(\.modelContext) private var context
//    @State private var showSettings = false
//    @State private var detailRef: MediaRef? = nil
//
//    // All tracked Movies
//    @Query(
//        filter: #Predicate<ProgressItem> { $0.isInWatchlist && $0.media.kindRaw == "movie" },
//        sort: [SortDescriptor(\ProgressItem.media.title, order: .forward)]
//    )
//    private var moviesFollowing: [ProgressItem]
//
//    // Tracked Movies you still need to watch
//    @Query(
//        filter: #Predicate<ProgressItem> { $0.isInWatchlist && !$0.watched && $0.media.kindRaw == "movie" },
//        sort: [SortDescriptor(\ProgressItem.media.title, order: .forward)]
//    )
//    private var moviesToWatch: [ProgressItem]
//
//    enum Segment: String, CaseIterable, Identifiable {
//        case following = "Following"
//        case toWatch   = "To Watch"
//        var id: String { rawValue }
//    }
//    @State private var segment: Segment = .following
//
//    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 12)]
//
//    var body: some View {
//        NavigationStack {
//            VStack {
////                Picker("", selection: $segment) {
////                    ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
////                }
////                .pickerStyle(.segmented)
////                .padding(.horizontal)
//
//                let items = segment == .following ? moviesFollowing : moviesToWatch
//
//                if items.isEmpty {
//                    ContentUnavailableView(
//                        segment == .following ? "No tracked movies yet" : "Nothing to watch",
//                        systemImage: "film",
//                        description: Text(segment == .following
//                                          ? "Add movies from Discover to start tracking."
//                                          : "You’re all caught up on the movies you follow.")
//                    )
//                    .frame(maxWidth: .infinity, maxHeight: .infinity)
//                } else {
//                    ScrollView {
//                        LazyVGrid(columns: cols, spacing: 12) {
//                            ForEach(items) { p in
//                                VStack(spacing: 6) {
//                                    PosterImage(path: p.media.posterPath)
//                                        .frame(width: 110, height: 165)
//                                        .clipShape(RoundedRectangle(cornerRadius: 12))
//                                        .clipped()
//
//                                    Text(p.media.title)
//                                        .font(.caption)
//                                        .lineLimit(2)
//                                        .frame(width: 110, alignment: .leading)
//                                }
//                                .contentShape(Rectangle())
//                                .contextMenu {
//                                    if p.watched {
//                                        Button("Mark Unwatched") { p.watched = false; try? context.save() }
//                                    } else {
//                                        Button("Mark Watched") { p.watched = true; try? context.save() }
//                                    }
//                                    Button("Remove from Watchlist") {
//                                        p.isInWatchlist = false
//                                        try? context.save()
//                                    }
//                                }
//                            }
//                        }
//                        .padding(.horizontal, 12)
//                        .padding(.top, 12)
//                    }
//                }
//            }
//            .navigationTitle("Movies")
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
//        }
//    }
//}
