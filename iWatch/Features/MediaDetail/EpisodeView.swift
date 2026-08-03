import Observation
import SwiftUI
import SwiftData

@MainActor
@Observable
private final class EpisodeScreenModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(EpisodeDetails)
        case failed(String)
    }

    let ref: EpisodeRef

    private let contentRepository: ContentRepository
    private let libraryRepository: LibraryRepository
    private let session: AppSession

    var loadState: LoadState = .idle
    var showTitle = ""
    var watchEventID: UUID?
    var isWatched = false
    var showFullOverview = false

    init(ref: EpisodeRef,
         contentRepository: ContentRepository,
         libraryRepository: LibraryRepository,
         session: AppSession) {
        self.ref = ref
        self.contentRepository = contentRepository
        self.libraryRepository = libraryRepository
        self.session = session
    }

    var details: EpisodeDetails? {
        if case let .loaded(details) = loadState {
            return details
        }
        return nil
    }

    var title: String {
        showTitle.isEmpty ? "Episode" : showTitle
    }

    var shareText: String {
        let episodeTitle = details?.name ?? "Episode"
        return "\(showTitle) • S\(ref.season)E\(ref.episode) • \(episodeTitle)"
    }

    var showRef: MediaID {
        MediaID(kind: .show, id: ref.showId, traktID: ref.showTraktID)
    }

    func load(forceRefresh: Bool = false) async {
        loadState = .loading

        do {
            let details = try await contentRepository.episodeDetails(for: ref, forceRefresh: forceRefresh)
            loadState = .loaded(details)

            if showTitle.isEmpty,
               case let .show(show) = try await contentRepository.details(
                for: MediaID(kind: .show, id: ref.showId, traktID: ref.showTraktID)
               ) {
                showTitle = show.common.title
            }

            await refreshLibraryState()
        } catch {
            guard !error.isCancelled else { return }
            loadState = .failed(error.localizedDescription)
        }
    }

    func refreshLibraryState() async {
        if let details {
            watchEventID = await libraryRepository.latestWatchEventID(for: details.mediaID)
            isWatched = watchEventID != nil
        } else {
            isWatched = await libraryRepository.isEpisodeWatched(ref)
        }
    }

    func toggleWatched() async {
        do {
            if let watchEventID {
                try await libraryRepository.removeWatchEvent(eventID: watchEventID)
            } else if let details {
                try await libraryRepository.addWatchEvent(for: details.mediaID, watchedAt: Date())
            } else if let tmdbID = ref.tmdbID {
                try await libraryRepository.addWatchEvent(
                    for: MediaID(kind: .episode, id: tmdbID, traktID: ref.traktID),
                    watchedAt: Date()
                )
            }

            session.markLibraryUpdated(syncIfConnected: true)
            await refreshLibraryState()
        } catch {
            guard !error.isCancelled else { return }
            loadState = .failed(error.localizedDescription)
        }
    }
}

struct EpisodeView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AppSession.self) private var session

    let ref: EpisodeRef

    @State private var model: EpisodeScreenModel?

    var body: some View {
        Group {
            if let model {
                EpisodeViewBody(model: model)
            } else {
                ProgressView()
                    .task {
                        let newModel = EpisodeScreenModel(
                            ref: ref,
                            contentRepository: container.contentRepository,
                            libraryRepository: container.libraryRepository,
                            session: session
                        )
                        await newModel.load()
                        guard !Task.isCancelled else { return }
                        model = newModel
                    }
            }
        }
    }
}

private struct EpisodeViewBody: View {
    @Bindable var model: EpisodeScreenModel
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            switch model.loadState {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .failed(let message):
                ContentUnavailableView("Episode Error",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(message))

            case .loaded(let details):
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        hero(details)
                        detailsSection(details)
                        actionsSection(details)
                        overviewSection(details)
                        creditsSection(details)
                    }
                    .padding(.bottom, 28)
                }
                .contentMargins(.horizontal, 20)
                .navigationTitle(model.title)
                .navigationBarTitleDisplayMode(.inline)
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
            }
        }
        .task(id: session.libraryRevision) {
            await model.refreshLibraryState()
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                NavigationLink {
                    MediaDetailView(ref: model.showRef)
                } label: {
                    Label("View Show", systemImage: "tv")
                }
            }
        }
    }

    @ViewBuilder
    private func hero(_ details: EpisodeDetails) -> some View {
        if let stillPath = details.stillPath {
            BackdropImage(path: stillPath)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .glassEffect(.regular, in: .rect(cornerRadius: 26))
                .padding(.horizontal, -15)
        } else {
            Color.clear
                .frame(height: 220)
        }
    }

    private func detailsSection(_ details: EpisodeDetails) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let episodeName = details.name.isEmpty ? "" : details.name
            let separator = episodeName.isEmpty ? "" : " • "

            Text("S\(model.ref.season) E\(model.ref.episode)\(separator)\(episodeName)")
                .font(.title2.bold())
                .fontDesign(.rounded)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            HStack(spacing: 14) {
                if let airDate = details.airDate {
                    Label(airDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                }
                if let runtime = details.extras?.runtime {
                    Label("\(runtime) min", systemImage: "clock")
                }
                if let rating = details.extras?.voteAverage {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionsSection(_ details: EpisodeDetails) -> some View {
        HStack(spacing: 12) {
            Button {
                Haptics.notification(.success)
                Task { await model.toggleWatched() }
            } label: {
                Label(model.isWatched ? "Watched" : "Mark Watched",
                      systemImage: model.isWatched ? "checkmark.circle.fill" : "checkmark.circle")
                    .bold()
                    .imageScale(.large)
                    .frame(width: 150, height: 30)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.isWatched ? .accentColor : .secondary)
            .glassEffect(.regular, in: .capsule)
            .clipShape(.capsule)

            Spacer()

            ShareLink(item: model.shareText, subject: Text(details.name.isEmpty ? "Episode" : details.name)) {
                Label("Share", systemImage: "square.and.arrow.up.fill")
                    .fontWeight(.semibold)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.white)
                    .imageScale(.large)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .glassEffect(.regular, in: .circle)
            .clipShape(.circle)
            .tint(.secondary)
        }
    }

    @ViewBuilder
    private func overviewSection(_ details: EpisodeDetails) -> some View {
        if let overview = details.overview, !overview.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Overview")
                    .font(.title3.bold())

                Text(overview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(model.showFullOverview ? nil : 4)

                if overview.count > 220 {
                    Button(model.showFullOverview ? "Show Less" : "Read More") {
                        withAnimation(.snappy) {
                            model.showFullOverview.toggle()
                        }
                    }
                    .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func creditsSection(_ details: EpisodeDetails) -> some View {
        let credits = mergedCredits(from: details.extras)
        if !credits.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cast & Crew")
                    .font(.title3.bold())

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(credits, id: \.id) { credit in
                            CastCard(
                                name: credit.name,
                                subtitle: credit.role ?? credit.job,
                                profilePath: credit.profilePath
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.horizontal, -20)
            }
        }
    }

    private func mergedCredits(from extras: EpisodeDetails.Extras?) -> [EpisodeDetails.Extras.Credit] {
        guard let extras else { return [] }

        let orderedCast = extras.cast.sorted { ($0.order ?? .max) < ($1.order ?? .max) }
        let sources = [orderedCast, extras.guestStars, extras.directors, extras.writers]

        var seen = Set<Int>()
        var merged: [EpisodeDetails.Extras.Credit] = []

        for source in sources {
            for credit in source where !seen.contains(credit.id) {
                seen.insert(credit.id)
                merged.append(credit)
            }
        }

        return merged
    }
}

private struct CastCard: View {
    let name: String
    let subtitle: String?
    let profilePath: String?

    var body: some View {
        VStack(spacing: 8) {
            ProfileImage(path: profilePath)
                .shadow(radius: 4)

            Text(name)
                .font(.caption.weight(.semibold))
                .lineLimit(2)

            Text(subtitle ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(width: 100)
        .multilineTextAlignment(.center)
    }
}

#Preview {
    @Previewable @State var showSheet = true
    let container = AppContainer.preview()

    Color.clear
        .background(Color.gray)
        .sheet(isPresented: $showSheet) {
            NavigationStack {
                EpisodeView(ref: EpisodeRef(showId: 1399, season: 1, episode: 1))
            }
        }
        .environment(container)
        .environment(container.session)
        .environment(container.router)
        .modelContainer(container.persistence.modelContainer)
}

// MARK: - Show IDs
// GoT: 1399
// Wednesday: 119051
// Peacemaker: 110492
// The Last of Us: 100088
