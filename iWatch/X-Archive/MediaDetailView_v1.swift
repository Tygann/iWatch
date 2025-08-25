// Views/MediaDetailView.swift
import SwiftUI

struct MediaDetailView1: View {
    let ref: MediaRef
    @EnvironmentObject private var env: AppEnvironment
    @State private var vm: MediaDetailViewModel?

    var body: some View {
        Group {
            if let vm {
                MediaDetailInnerView(vm: vm)   // stable view does the loading
            } else {
                ProgressView()
                    .task { vm = MediaDetailViewModel(env: env, ref: ref) } // just create
            }
        }
        .navigationBarTitleDisplayMode(.inline)
//        .toolbar(.hidden, for: .navigationBar)   // <-- hide the nav bar completely
    }
}

private struct MediaDetailInnerView: View {
    @ObservedObject var vm: MediaDetailViewModel

    var body: some View {
        Group {
            if let d = vm.detail {
                // ----- Loaded content -----
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        PosterHero(backdropPath: d.backdropPath, posterPath: d.posterPath)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(d.title).font(.title.bold())
                            HStack(spacing: 12) {
                                if let year = d.releaseYear { Label(year, systemImage: "calendar") }
                                if let mins = d.runtimeMinutes { Label("\(mins) min", systemImage: "clock") }
                                if let rating = d.rating { Label(String(format: "%.1f", rating), systemImage: "star.fill") }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                            if let tagline = d.tagline {
                                Text(tagline).font(.callout.italic()).foregroundStyle(.secondary)
                            }
                            if !d.genres.isEmpty {
                                Text(d.genres.joined(separator: " • "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal)

                        if let overview = d.overview {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Overview").font(.title3.bold())
                                Text(overview)
                            }
                            .padding(.horizontal)
                        }

                        if d.kind == .tv, let seasons = d.seasons, !seasons.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Seasons").font(.title3.bold()).padding(.horizontal)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 12) {
                                        ForEach(seasons) { s in
                                            NavigationLink {
//                                                SeasonDetailView(tvID: d.id, seasonNumber: s.seasonNumber)
                                            } label: {
                                                VStack(alignment: .leading, spacing: 8) {
                                                    PosterImage(path: s.posterPath)
                                                        .frame(width: 120, height: 180)
                                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                                    Text(s.name)
                                                        .font(.subheadline.weight(.semibold))
                                                        .lineLimit(2)
                                                    if let c = s.episodeCount {
                                                        Text("\(c) episodes")
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                                .frame(width: 120, alignment: .leading)
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
//                .navigationTitle(d.title)
                .ignoresSafeArea(edges: .top)

            } else if let error = vm.errorText {
                // ----- Error state -----
                ContentUnavailableView(
                    "Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )

            } else {
                // ----- Initial/Loading default -----
                ProgressView()
            }
        }
        // Start the load when this inner view is on screen (won’t be cancelled)
        .task { await vm.load() }
    }
}

// MARK: - Poster Hero
private struct PosterHero: View {
    let backdropPath: String?
    let posterPath: String?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            BackdropImage(path: backdropPath)
                .frame(height: 220)
//                .frame(height: 260) // bump taller
                .clipped()
                .overlay( // subtle bottom fade for readability
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.35)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            
            HStack(alignment: .bottom, spacing: 16) {
                PosterImage(path: posterPath)
                    .frame(width: 120, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 6)
                Spacer()
            }
            .padding(.horizontal)
            .offset(y: 40)
        }
        .padding(.bottom, 40)
    }
}

// MARK: - Season Detail
struct SeasonDetailView1: View {
    let tvID: Int
    let seasonNumber: Int
    var body: some View {
        Text("Season \(seasonNumber)").navigationTitle("Season \(seasonNumber)")
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
}

// MARK: - Previewer Helper
private struct PreviewTrendingDetail: View {
    let kind: MediaRef.Kind
    @EnvironmentObject private var env: AppEnvironment
    @State private var ref: MediaRef?

    var body: some View {
        Group {
            if let ref { MediaDetailView1(ref: ref) }
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
