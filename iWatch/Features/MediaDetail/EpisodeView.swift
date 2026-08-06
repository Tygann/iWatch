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

    var episodeTitle: String {
        guard let name = details?.name, !name.isEmpty else { return "Episode" }
        return name
    }

    var shareText: String {
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
    let onClose: (() -> Void)?

    @State private var model: EpisodeScreenModel?

    init(ref: EpisodeRef, onClose: (() -> Void)? = nil) {
        self.ref = ref
        self.onClose = onClose
    }

    var body: some View {
        Group {
            if let model {
                EpisodeViewBody(model: model, onClose: onClose)
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
    private enum Layout {
        static let navigationTitleOffset: CGFloat = 180
    }

    @Bindable var model: EpisodeScreenModel
    let onClose: (() -> Void)?
    @Environment(AppSession.self) private var session

    @State private var scrollOffset: CGFloat = 0

    private var showsNavigationTitle: Bool {
        scrollOffset > Layout.navigationTitleOffset
    }

    private var bannerShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 26,
            bottomTrailingRadius: 26,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    // MARK: - Body
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
                        bannerSection(details)
                        VStack(alignment: .leading, spacing: 16) {
                            metadataSection(details)
                            actionsSection(details)
                            overviewSection(details)
                            creditsSection(details)
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 28)
                }
                .navigationTitle(showsNavigationTitle ? model.episodeTitle : "")
                .navigationBarTitleDisplayMode(.inline)
                .ignoresSafeArea(edges: details.stillPath == nil ? [] : .top)
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
                .scrollEdgeEffectHidden(!showsNavigationTitle, for: .top)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, offset in
                    scrollOffset = offset
                }
            }
        }
        .task(id: session.libraryRevision) {
            await model.refreshLibraryState()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    NavigationLink {
                        MediaDetailView(ref: model.showRef, onClose: onClose)
                    } label: {
                        Label("View Show", systemImage: "tv")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")

                if let onClose {
                    Button(role: .close, action: onClose)
                }
            }
        }
    }

    // MARK: - Banner Section
    @ViewBuilder
    private func bannerSection(_ details: EpisodeDetails) -> some View {
        if let stillPath = details.stillPath {
            BackdropImage(path: stillPath)
                .frame(height: 220)
                .clipShape(bannerShape)
                .backgroundExtensionEffect()
                .safeAreaInset(edge: .top) {
                    EmptyView()
                        .padding(25)
                }
                .clipped()
                .glassEffect(.regular, in: bannerShape)
                .stretchy()
        } else {
            Color.clear
                .frame(height: 220)
        }
    }

    // MARK: - Metadata Section
    private func metadataSection(_ details: EpisodeDetails) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.showTitle.isEmpty {
                Text(model.showTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

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

    // MARK: - Actions Section
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

    // MARK: - Overview Section
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

    // MARK: - Credits Section
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
                            MediaCreditCard(
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

    // MARK: - Helpers
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

// MARK: - Previews
#Preview("Standard") {
    let container = AppContainer.preview()

    NavigationStack {
        EpisodeView(
            ref: EpisodeRef(showId: 1399, season: 1, episode: 1)
        )
    }
    .environment(container)
    .environment(container.session)
    .environment(container.router)
    .modelContainer(container.persistence.modelContainer)
}

#Preview("Sheet") {
    @Previewable @State var showSheet = true
    let container = AppContainer.preview()

    Color.clear
        .background(Color.gray)
        .sheet(isPresented: $showSheet) {
            NavigationStack {
                EpisodeView(
                    ref: EpisodeRef(showId: 1399, season: 1, episode: 1),
                    onClose: { showSheet = false }
                )
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
