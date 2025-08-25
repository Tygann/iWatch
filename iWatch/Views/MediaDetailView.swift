// Views/MediaDetailView.swift
import SwiftUI
import SwiftData

struct MediaDetailView: View {
    let ref: MediaRef
    @EnvironmentObject private var env: AppEnvironment
    @State private var vm: MediaDetailViewModel? = nil
    @State private var scrollOffset: CGFloat = 0
    @State private var expandedSeason: Int? = nil
    @Environment(\.modelContext) private var modelContext
    @State private var watched: [String: Bool] = [:] // key: "{mediaID}-S{season}-E{episode}"
    
    // MARK: - View Body
    var body: some View {
        Group {
            if let vm, let data = vm.viewData {
                ScrollView {
                    VStack(spacing: 14) {
                        headerSection
                        introSection
                        statsSection
                        overviewSection
                        seasonsSection
                    }
                }
                .navigationTitle(scrollOffset > 450 ? data.title : "")
                .navigationBarTitleDisplayMode(.inline)
                .ignoresSafeArea(edges: .top)
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, newValue in
                    scrollOffset = newValue
                }
            } else if let vm, let error = vm.errorText {
                ContentUnavailableView(
                    "Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ProgressView()
            }
        }
        .task {
            if vm == nil {
                let model = MediaDetailViewModel(env: env, ref: ref)
                await model.load()
                await MainActor.run { vm = model }
            }
        }
    }
    
    // MARK: - Header Sections
    private var headerSection: some View {
        Group {
            if let backdrop = vm?.viewData?.backdropPath {
                BackdropImage(path: backdrop)
                    .stretchy()
            }
        }
    }

    // MARK: - Intro Section
    private var introSection: some View {
        Group {
            if let d = vm?.viewData {
                HStack(alignment: .top, spacing: 16) {
                    // Poster
                    PosterImage(path: d.posterPath)
                        .frame(width: 120, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 6)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        // Title
                        Text(d.title)
                            .font(.title2.bold())
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        
                        // Tagline
                        if let tagline = d.tagline {
                            Text(tagline)
                        }
                        
                        Spacer()
                        
                        // Watchlist Button
                        Button("Following") {
                            // Action here
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 9)
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    // MARK: - Stats Section
    private var statsSection: some View {
        Group {
            Divider().padding(.horizontal, 14)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    // Rating
                    if let rating = vm?.viewData?.rating {
                        let stars = rating / 2.0 // Convert to 5-star scale
                        VStack {
                            detailItem(title: "RATING", value: String(format: "%.1f", stars))
                            StarRating(rating: 4.5, maxRating: 5)
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                        Divider().frame(height: 34).padding(.horizontal, 12)
                    }
                    
                    // Release Date
                    if let releaseDate = vm?.viewData?.releaseYear {
                        detailItem(title: "YEAR", value: releaseDate)
                        Divider().frame(height: 34).padding(.horizontal, 12)
                    }
                    
                    // Runetime
                    if let mins = vm?.viewData?.runtimeMinutes {
                        detailItem(title: "RUNTIME", value: "\(mins) min")
                        Divider().frame(height: 34).padding(.horizontal, 12)
                    }
                    
                    // Genres
                    if let genres = vm?.viewData?.genres, !genres.isEmpty {
                        detailItem(title: "GENRES", value: genres.joined(separator: " • "))
                    }
                }
                .padding(.horizontal, 20)
            }
            Divider().padding(.horizontal, 14)
        }
    }
    
    private func detailItem(title: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
    }
    
    // MARK: - Overview Section
    private var overviewSection: some View {
        Group {
            if let d = vm?.viewData {
                @State var isExpanded: Bool = false
                @State var titleHeight: CGFloat = 0
                let collapsedLines: Int = {
                    let posterHeight: CGFloat = 180
                    let spacingBelowTitle: CGFloat = 6
                    let available = max(0, posterHeight - titleHeight - spacingBelowTitle)
                    let lineHeight = UIFont.preferredFont(forTextStyle: .callout).lineHeight
                    return max(1, Int(floor(available / lineHeight)) - 3)
                }()
                
                if let overview = d.overview, !overview.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Overview")
                            .font(.title3.bold())
                        expandableText(
                            overview,
                            isExpanded: Binding(get: { isExpanded }, set: { isExpanded = $0 }),
                            collapsedLineLimit: collapsedLines,
                            showMoreThreshold: 250
                        )
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
    
    @ViewBuilder private func expandableText(_ text: String, isExpanded: Binding<Bool>, collapsedLineLimit: Int = 5, showMoreThreshold: Int = 140) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded.wrappedValue ? nil : collapsedLineLimit)
                    .fixedSize(horizontal: false, vertical: true)

                if text.count > showMoreThreshold && !isExpanded.wrappedValue {
                    ZStack(alignment: .trailing) {
                        Rectangle()
                            .fill(Color(.systemBackground))
                            .frame(width: 44, height: 22)
                            .allowsHitTesting(false)
                        LinearGradient(
                            colors: [Color.clear, Color(.systemBackground)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 120, height: 22)
                        .allowsHitTesting(false)
                        Button("more") { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.wrappedValue = true } }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tint)
                            .buttonStyle(.plain)
                    }
                    .zIndex(1)
                    .frame(height: 22, alignment: .bottom)
                    .offset(y: 1)
                }
            }
            if text.count > showMoreThreshold && isExpanded.wrappedValue {
                Button { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.wrappedValue = false } } label: {
                    Text("less")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Seasons Section
    private var seasonsSection: some View {
        Group {
            if let d = vm?.viewData, d.isTV, !d.seasons.isEmpty, let vm = vm {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Seasons")
                        .font(.title3.bold())
                        .padding(.horizontal, 20)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(d.seasons) { season in
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedSeason == season.seasonNumber },
                                    set: { newValue in
                                        expandedSeason = newValue ? season.seasonNumber : nil
                                    }
                                ),
                                content: {
                                    if season.episodes.isEmpty {
                                        Text("No episodes available.")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .padding(.vertical, 4)
                                    } else {
                                        LazyVStack(alignment: .leading, spacing: 12) {
                                            ForEach(season.episodes) { ep in
                                                episodeRow(episode: ep, mediaID: d.id, seasonNumber: season.seasonNumber)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                },
                                label: {
                                    HStack {
                                        PosterImage(path: season.posterPath)
                                        Text(season.name.isEmpty ? "Season \(season.seasonNumber)" : season.name)
                                        Spacer()
                                        if let c = season.episodeCount { Text("\(c) eps").foregroundStyle(.secondary) }
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder private func episodeRow(episode: MediaDetailViewModel.ViewData.Episode, mediaID: Int, seasonNumber: Int) -> some View {
        let key = "\(mediaID)-S\(seasonNumber)-E\(episode.episodeNumber)"
        let isWatched = watched[key] ?? false
        HStack(alignment: .top, spacing: 12) {
            PosterImage(path: episode.stillPath, width: 120, height: 68)
            VStack(alignment: .leading, spacing: 4) {
                Text("E\(episode.episodeNumber) • \(episode.name)")
                    .font(.headline)
                if let airDate = episode.dateAirDate?.formatted(date: .abbreviated, time: .omitted) {
                    Text(airDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                toggleWatched(key: key, mediaID: mediaID, season: seasonNumber, episodeNumber: episode.episodeNumber)
            } label: {
                Image(systemName: isWatched ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isWatched ? Color.accentColor : Color.secondary)
                    .accessibilityLabel(isWatched ? "Mark as unwatched" : "Mark as watched")
            }
            .buttonStyle(.plain)
        }
        .task {
            await loadWatchedState(key: key)
        }
    }
    
    // MARK: - Watched State (SwiftData helpers)
    private func loadWatchedState(key: String) async {
        do {
            var descriptor = FetchDescriptor<EpisodeProgress>(
                predicate: #Predicate { $0.key == key }
            )
            descriptor.fetchLimit = 1
            let existing = try modelContext.fetch(descriptor).first
            await MainActor.run {
                watched[key] = existing?.watched ?? false
            }
        } catch {
            #if DEBUG
            print("loadWatchedState error:", error)
            #endif
        }
    }

    private func toggleWatched(key: String, mediaID: Int, season: Int, episodeNumber: Int) {
        do {
            var descriptor = FetchDescriptor<EpisodeProgress>(
                predicate: #Predicate { $0.key == key }
            )
            descriptor.fetchLimit = 1
            if let existing = try modelContext.fetch(descriptor).first {
                existing.watched.toggle()
                existing.watchedAt = existing.watched ? Date() : nil
                watched[key] = existing.watched
            } else {
                let progress = EpisodeProgress(mediaID: mediaID, season: season, episode: episodeNumber, watched: true, watchedAt: Date())
                modelContext.insert(progress)
                watched[key] = true
            }
            try modelContext.save()
        } catch {
            #if DEBUG
            print("toggleWatched error:", error)
            #endif
        }
    }
}

// MARK: - Previewer Helper
private struct PreviewTrendingDetail: View {
    let kind: MediaRef.Kind
    @EnvironmentObject private var env: AppEnvironment
    @State private var ref: MediaRef?

    var body: some View {
        Group {
            if let ref { MediaDetailView(ref: ref) }
            else { ProgressView().task { await load() } }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .close) { }
            }
        }
    }

    @MainActor
    private func load() async {
        do {
            switch kind {
            case .movie:
                if let first = try await env.contentAPI.trendingMovies(page: 1)
                    .first(where: { $0.posterPath != nil }) {
                    ref = .init(id: first.id, kind: .movie)
                }
            case .tv:
                if let first = try await env.contentAPI.trendingTV(page: 1)
                    .first(where: { $0.posterPath != nil }) {
                    ref = .init(id: first.id, kind: .tv)
                }
            }
        } catch {
            #if DEBUG
            print("Preview load failed:", error)
            #endif
        }
    }
}

// MARK: - Preview Provider
#Preview {
    @Previewable @State var showSheet = true
    // Empty host that just presents the sheet
    Color.clear
//        .background(Color.black.opacity(0.001)) // keep it visible in canvas
        .background(Color.gray) // keep it visible in canvas
        .sheet(isPresented: $showSheet) {
//            // Instant (Mock)
//            NavigationStack { MediaDetailInnerView(vm: .previewData) }
//                .environmentObject(AppEnvironment.preview)
//
//            // Live Movie (Trending)
//            NavigationStack { PreviewTrendingDetail(kind: .movie) }
//                .environmentObject(AppEnvironment.previewSmart)
            
            // Live Show (Trending)
            NavigationStack { PreviewTrendingDetail(kind: .tv) }
                .environmentObject(AppEnvironment.previewSmart) // uses TMDB if key exists
        }
    
    
//    NavigationStack { PreviewTrendingDetail(kind: .tv) }
//        .environmentObject(AppEnvironment.previewSmart) // uses TMDB if key exists
}
