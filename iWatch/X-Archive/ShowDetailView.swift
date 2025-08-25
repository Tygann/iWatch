//// Features/Shows/ShowDetailView.swift
//import SwiftUI
//import SwiftData
//import SafariServices
//
//// MARK: - Show Detail View
//struct ShowDetailView: View {
//    // Environment
//    @EnvironmentObject private var env: AppEnvironment
//    @Environment(\.modelContext) private var context
//
//    // Input
//    let progress: ProgressItem        // the tracked show
//    private var media: MediaItem { progress.media }
//
//    // Remote state
//    @State private var details: TVDetailsDTO?
//    @State private var seasons: [Int: [TVSeasonDTO.EpisodeDTO]] = [:]  // seasonNumber -> episodes
//    @State private var trailerURL: URL?
//
//    // Local progress cache
//    @State private var watchedSet: Set<String> = [] // "\(s)-\(e)"
//
//    // UI state
//    @State private var isLoading = true
//    @State private var error: String?
//
//    // MARK: - View Body
//    var body: some View {
//        List {
//            header
//            bodySections
//        }
//        .navigationTitle(media.title)
//        .navigationBarTitleDisplayMode(.inline)
//        .task { await load() }
////        .toolbar {
////            if trailerURL != nil {
////                ToolbarItem(placement: .primaryAction) {
////                    Link(destination: trailerURL!) {
////                        Image(systemName: "play.rectangle.fill")
////                    }
////                    .accessibilityLabel("Watch trailer")
////                }
////            }
////        }
//        .scrollContentBackground(.hidden)
//    }
//
//    // MARK: - Header
//    private var header: some View {
//        Section {
//            VStack(spacing: 10) {
//                Spacer(minLength: 4)
//                
//                PosterImage(path: media.posterPath)
//                    .frame(width: 140, height: 210)
//                    .clipShape(RoundedRectangle(cornerRadius: 14))
//                    .shadow(radius: 8)
//                
//                Text(media.title)
//                    .font(.title2.weight(.semibold))
//                    .multilineTextAlignment(.center)
//                    .padding(.horizontal)
//                
//                if let ov = details?.overview, !ov.isEmpty {
//                    Text(ov)
//                        .font(.callout)
//                        .foregroundStyle(.secondary)
//                        .multilineTextAlignment(.center)
//                        .padding(.horizontal)
//                }
//                
//                Spacer(minLength: 8)
//            }
//            .frame(maxWidth: .infinity)
////           .background(backdropView)
////           .clipShape(RoundedRectangle(cornerRadius: 16))
//            .padding(.horizontal)
//        }
////        .listRowBackground(Color.clear)
//        .listRowBackground(backdropView)
////        .listRowInsets(.init(top: 12, leading: 0, bottom: 12, trailing: 0))
//        .listRowInsets(EdgeInsets())
//    }
//    
//    // MARK: - Backdrop
//    private var backdropView: some View {
//        Group {
//            if let path = details?.backdrop_path {
//                PosterImage(path: path, size: "w780")
//                    .scaledToFill()
//                    .overlay(
//                        LinearGradient(
//                            colors: [.black.opacity(0.55), .black.opacity(0.6)],
//                            startPoint: .top, endPoint: .bottom
//                        )
//                    )
//                    .blur(radius: 20)
//            } else {
//                LinearGradient(
//                    colors: [.black, .black.opacity(0.85)],
//                    startPoint: .top, endPoint: .bottom
//                )
//            }
//        }
//    }
//    
//    // MARK: - Body Sections
//    private var bodySections: some View {
//        Group {
//            if let _ = details {
//                about
//                trailerButton
//                episodesSection
//            } else if isLoading {
//                LoadingView().frame(maxWidth: .infinity, minHeight: 120)
//            } else if let error {
//                ErrorView(message: error).frame(maxWidth: .infinity)
//            }
//        }
//    }
//
//    // MARK: About
//    private var about: some View {
//        Section("Overview") {
//            if let d = details {
//                VStack(alignment: .leading, spacing: 4) {
//                    if let n = d.networks.first?.name {
//                        LabeledContent("Network", value: n)
//                    }
//                    LabeledContent("Seasons", value: "\(d.number_of_seasons)")
//                    LabeledContent("Episodes", value: "\(d.number_of_episodes)")
//                }
//            }
//        }
//    }
//    
//    // MARK: Trailer
//    private var trailerButton: some View {
//        Section {
//            if let url = trailerURL {
//                Link(destination: url) {
//                    HStack {
//                        Image(systemName: "play.rectangle.fill").imageScale(.large)
//                        Text("Watch Trailer").fontWeight(.semibold)
//                        Spacer()
//                        Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
//                    }
//                }
//                .buttonStyle(.plain)
//            }
//        }
//    }
//
//    // MARK: Episodes
//    private var episodesSection: some View {
//        Group {
//            if let d = details {
//                
//                // Order: Specials(0) first if present, then 1..N
//                let orderedSeasons = d.seasons
//                    .map(\.season_number)
//                    .sorted { (a, b) in (a == 0 && b != 0) || (a != 0 && b != 0 && a < b) }
//                
//                Section("Episodes") {
//                    ForEach(orderedSeasons, id: \.self) { s in
//                        DisclosureGroup(s == 0 ? "Specials" : "Season \(s)") {
//                            seasonEpisodesView(season: s)
//                                .task { await ensureSeasonLoaded(s) }
//                        }
//                    }
//                }
//            }
//        }
//    }
//
//    
////    private func listItem(for festival: Festival) -> some View {
////        HStack {
////            LogoImage(festival: festival)
////                .frame(width: 40, height: 40)
////                .clipShape(Circle())
////                .shadow(radius: 3)
////
////            Text(festival.name)
////                .fontDesign(.rounded)
////                .padding(.trailing, showActiveIndicator ? 0.4 : 0)
////
////            // MARK: iPad Only
////            if horizontalSizeClass == .regular {
////                if showActiveIndicator {
////                    Spacer()
////                    ActiveIndicator(festival: festival)
////                }
////            }
////        }
////    }
//    
//    
//    private func seasonEpisodesView(season: Int) -> some View {
//        Group {
//            if let eps = seasons[season] {
//                ForEach(eps) { ep in
//                    EpisodeRow(
//                        title: ep.name,
//                        subtitle: ep.air_date ?? "",
//                        stillPath: ep.still_path,
//                        watched: watchedSet.contains(key(season: season, episode: ep.episode_number))
//                    ) {
//                        toggleEpisode(season: season, episode: ep.episode_number)
//                    }
//                }
//            } else {
//                HStack { ProgressView(); Text("Loading…") }
//            }
//        }
//    }
//
//    // MARK: Loading
//    @MainActor
//    private func load() async {
//        isLoading = true; error = nil
//        do {
//            // details
//            let d = try await env.contentAPI.tvDetails(id: media.remoteID)
//            self.details = d
//
//            // trailer (YouTube)
//            let vids = try await env.contentAPI.tvVideos(id: media.remoteID).results
//            if let yt = vids.first(where: { $0.site == "YouTube" && $0.type == "Trailer" }) {
//                self.trailerURL = URL(string: "https://www.youtube.com/watch?v=\(yt.key)")
//            }
//
//            // preload watched states from SwiftData
//            preloadWatched()
//
//            isLoading = false
//        } catch {
//            self.error = "Failed to load show."
//            isLoading = false
//        }
//    }
//
//    private func ensureSeasonLoaded(_ s: Int) async {
//        guard seasons[s] == nil else { return }
//        do {
//            let dto = try await env.contentAPI.tvSeason(id: media.remoteID, season: s)
//            await MainActor.run { seasons[s] = dto.episodes }
//        } catch { /* swallow per-season error */ }
//    }
//
//    private func preloadWatched() {
//        let mid = progress.media.id            // bind outside the predicate
//        let fetch = FetchDescriptor<EpisodeProgress>(
//            predicate: #Predicate<EpisodeProgress> { $0.mediaID == mid }
//        )
//        if let rows = try? context.fetch(fetch) {
//            watchedSet = Set(rows.map { key(season: $0.season, episode: $0.episode) })
//        }
//    }
//
//    private func toggleEpisode(season: Int, episode: Int) {
//        let k = key(season: season, episode: episode)
//        let mid = progress.media.id            // bind all externals
//        let s = season
//        let e = episode
//
//        if watchedSet.contains(k) {
//            watchedSet.remove(k)
//            let fetch = FetchDescriptor<EpisodeProgress>(
//                predicate: #Predicate<EpisodeProgress> { $0.mediaID == mid && $0.season == s && $0.episode == e }
//            )
//            if let row = try? context.fetch(fetch).first {
//                row.watched = false
//                row.watchedAt = nil
//                try? context.save()
//            }
//            Task { await recomputeHasUnwatched() }
//            return
//        }
//
//        // add or update
//        watchedSet.insert(k)
//        let fetch = FetchDescriptor<EpisodeProgress>(
//            predicate: #Predicate<EpisodeProgress> { $0.mediaID == mid && $0.season == s && $0.episode == e }
//        )
//        if let row = try? context.fetch(fetch).first {
//            row.watched = true
//            row.watchedAt = Date()
//            try? context.save()
//        } else {
//            let row = EpisodeProgress(mediaID: mid, season: s, episode: e, watched: true, watchedAt: Date())
//            context.insert(row)
//            try? context.save()
//        }
//
//        Task { await recomputeHasUnwatched() }
//    }
//
//    @MainActor
//    private func recomputeHasUnwatched() async {
//        // If we have any loaded season where at least one ep is not watched -> true
//        let anyUnwatched = seasons.values.contains { eps in
//            eps.contains { !watchedSet.contains(key(season: $0.season_number ?? 0, episode: $0.episode_number)) }
//        }
//        progress.hasUnwatched = anyUnwatched
//        try? context.save()
//    }
//
//    private func key(season: Int, episode: Int) -> String { "\(season)-\(episode)" }
//}
//
//// MARK: - Episode row
//private struct EpisodeRow: View {
//    let title: String
//    let subtitle: String
//    let stillPath: String?
//    var watched: Bool
//    var onToggle: () -> Void
//
//    var body: some View {
//        HStack(spacing: 12) {
//            PosterImage(path: stillPath, size: "w300")
//                .frame(width: 120, height: 68)
//                .clipShape(RoundedRectangle(cornerRadius: 8))
//                .clipped()
//
//            VStack(alignment: .leading, spacing: 2) {
//                Text(title).font(.body)
//                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
//            }
//            Spacer()
//            Button {
//                onToggle()
//            } label: {
//                Image(systemName: watched ? "checkmark.circle.fill" : "circle")
//                    .imageScale(.large)
//            }
//            .buttonStyle(.plain)
//        }
//        .padding(.vertical, 4)
//    }
//}
