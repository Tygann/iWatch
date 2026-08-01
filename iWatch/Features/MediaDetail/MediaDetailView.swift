import Observation
import SwiftUI
import SwiftData

@MainActor
@Observable
private final class MediaDetailScreenModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(MediaDetails)
        case failed(String)
    }

    let ref: MediaID

    private let contentRepository: ContentRepository
    private let libraryRepository: LibraryRepository
    private let session: AppSession

    var loadState: LoadState = .idle
    var expandedSeason: Int?
    var isInWatchlist = false
    var overviewExpanded = false
    var movieWatchEventID: UUID?
    var watchedEpisodeKeys: Set<String> = []
    var remainingReleasedEpisodes = 0
    var nextEpisode: ShowProgress.NextEpisode?
    var episodesBySeason: [Int: [EpisodeDetails]] = [:]
    var loadingSeasons: Set<Int> = []

    var isMovieWatched: Bool {
        movieWatchEventID != nil
    }

    var shareText: String {
        if let details = currentDetails {
            return details.title
        }
        return "iWatch"
    }

    private var currentDetails: MediaDetails? {
        if case let .loaded(details) = loadState {
            return details
        }
        return nil
    }

    init(ref: MediaID,
         contentRepository: ContentRepository,
         libraryRepository: LibraryRepository,
         session: AppSession) {
        self.ref = ref
        self.contentRepository = contentRepository
        self.libraryRepository = libraryRepository
        self.session = session
    }

    func load(forceRefresh: Bool = false) async {
        loadState = .loading

        do {
            let details = try await contentRepository.details(for: ref, forceRefresh: forceRefresh)
            loadState = .loaded(details)

            await refreshLibraryState()

            if expandedSeason == nil,
               case let .show(show) = details {
                let availableSeasonNumbers = Set(show.seasons.map(\.seasonNumber))
                expandedSeason = nextEpisode
                    .map(\.season)
                    .flatMap { availableSeasonNumbers.contains($0) ? $0 : nil }
                    ?? show.seasons
                        .filter { $0.seasonNumber > 0 }
                        .map(\.seasonNumber)
                        .min()
                    ?? show.seasons
                        .filter { $0.seasonNumber >= 0 }
                        .map(\.seasonNumber)
                        .min()
            }

            if let expandedSeason,
               case .show = details {
                await loadSeason(expandedSeason)
            }
        } catch {
            guard !error.isCancelled else { return }
            loadState = .failed(error.localizedDescription)
        }
    }

    func refreshLibraryState() async {
        isInWatchlist = await libraryRepository.isInWatchlist(ref)

        switch ref.kind {
        case .movie:
            movieWatchEventID = await libraryRepository.latestWatchEventID(for: ref)

        case .show:
            do {
                let progress = try await libraryRepository.showProgress(for: ref)
                watchedEpisodeKeys = progress.watchedEpisodeKeys
                remainingReleasedEpisodes = progress.remainingReleased
                nextEpisode = progress.nextEpisode
            } catch {
                watchedEpisodeKeys = []
                remainingReleasedEpisodes = 0
                nextEpisode = nil
            }

        default:
            break
        }
    }

    func loadSeason(_ seasonNumber: Int, forceRefresh: Bool = false) async {
        guard case let .loaded(details) = loadState,
              case .show(let show) = details else {
            return
        }

        if loadingSeasons.contains(seasonNumber) {
            return
        }
        if episodesBySeason[seasonNumber] != nil, !forceRefresh {
            return
        }

        loadingSeasons.insert(seasonNumber)
        defer { loadingSeasons.remove(seasonNumber) }

        do {
            episodesBySeason[seasonNumber] = try await contentRepository.episodes(
                for: MediaID(kind: .show, id: show.common.id, traktID: show.common.traktID),
                seasonNumber: seasonNumber,
                forceRefresh: forceRefresh
            )
            await refreshLibraryState()
        } catch {
            guard !error.isCancelled else { return }
            loadState = .failed(error.localizedDescription)
        }
    }

    func toggleSeason(_ seasonNumber: Int) {
        expandedSeason = expandedSeason == seasonNumber ? nil : seasonNumber
    }

    func toggleWatchlist() async {
        do {
            try await libraryRepository.setWatchlist(!isInWatchlist, for: ref)
            isInWatchlist.toggle()
            session.markLibraryUpdated(syncIfConnected: true)
        } catch {
            guard !error.isCancelled else { return }
            loadState = .failed(error.localizedDescription)
        }
    }

    func toggleMovieWatched() async {
        do {
            if let movieWatchEventID {
                try await libraryRepository.removeWatchEvent(eventID: movieWatchEventID)
            } else {
                try await libraryRepository.addWatchEvent(for: ref, watchedAt: Date())
            }
            session.markLibraryUpdated(syncIfConnected: true)
            await refreshLibraryState()
        } catch {
            guard !error.isCancelled else { return }
            loadState = .failed(error.localizedDescription)
        }
    }

    func toggleEpisodeWatched(_ episode: EpisodeDetails) async {
        do {
            if let eventID = await libraryRepository.latestWatchEventID(for: episode.mediaID) {
                try await libraryRepository.removeWatchEvent(eventID: eventID)
            } else {
                try await libraryRepository.addWatchEvent(for: episode.mediaID, watchedAt: Date())
            }
            session.markLibraryUpdated(syncIfConnected: true)
            await refreshLibraryState()
        } catch {
            guard !error.isCancelled else { return }
            loadState = .failed(error.localizedDescription)
        }
    }

    func isEpisodeWatched(_ episode: EpisodeDetails) -> Bool {
        watchedEpisodeKeys.contains(episodeKey(for: episode))
    }

    func watchedCount(in seasonNumber: Int) -> Int {
        episodesBySeason[seasonNumber]?.filter(isEpisodeWatched(_:)).count ?? 0
    }

    func releaseLabel(for date: Date?) -> String? {
        guard let date else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func episodeKey(for episode: EpisodeDetails) -> String {
        "ep:\(ref.tmdbID):S\(episode.seasonNumber):E\(episode.episodeNumber)"
    }
}

struct MediaDetailView: View {
    let ref: MediaRef

    @Environment(AppContainer.self) private var container
    @Environment(AppSession.self) private var session

    @State private var model: MediaDetailScreenModel?

    var body: some View {
        Group {
            if let model {
                MediaDetailBody(model: model)
            } else {
                ProgressView()
                    .task {
                        let newModel = MediaDetailScreenModel(
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

private struct MediaDetailBody: View {
    @Bindable var model: MediaDetailScreenModel
    @Environment(AppSession.self) private var session
    @Namespace private var seasonIndicatorNamespace

    @State private var scrollOffset: CGFloat = 0
    @State private var overviewFullLines = 0

    var body: some View {
        Group {
            switch model.loadState {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .failed(let message):
                ContentUnavailableView("Unable to Load",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(message))

            case .loaded(let details):
                ScrollView {
                    VStack(spacing: 16) {
                        headerSection(details)
                        introSection(details)
                        detailsSection(details)
                        overviewSection(details)
                        seasonsSection(details)
                    }
                }
                .navigationTitle(scrollOffset > 350 ? details.title : "")
                .navigationBarTitleDisplayMode(.inline)
                .ignoresSafeArea(edges: .top)
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
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
    }

    @ViewBuilder
    private func headerSection(_ details: MediaDetails) -> some View {
        if let backdropPath = details.backdropPath {
            BackdropImage(path: backdropPath)
                .backgroundExtensionEffect()
                .safeAreaInset(edge: .top) {
                    EmptyView()
                        .padding(25)
                }
                .clipped()
                .stretchy()
        }
    }

    private func introSection(_ details: MediaDetails) -> some View {
        HStack(alignment: .top, spacing: 16) {
            PosterImage(path: details.posterPath)
                .frame(width: 120, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 6)

            VStack(alignment: .leading, spacing: 8) {
                Text(details.title)
                    .font(.title2.bold())
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                if let tagline = details.tagline, !tagline.isEmpty {
                    Text(tagline)
                }

                Spacer()

                Button {
                    Haptics.notification(.success)
                    Task { await model.toggleWatchlist() }
                } label: {
                    Text(model.isInWatchlist ? "In Watchlist" : "Add to Watchlist")
                        .bold()
                        .frame(minWidth: 90, minHeight: 25)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .glassEffect(.regular, in: .capsule)
                .clipShape(.capsule)
                .tint(model.isInWatchlist ? Color.accentColor : Color.secondary)
                .accessibilityLabel(model.isInWatchlist ? "Remove from watchlist" : "Add to watchlist")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func detailsSection(_ details: MediaDetails) -> some View {
        let hasMetadata = details.rating != nil
            || details.releaseDate != nil
            || details.movieRuntimeMinutes != nil
            || details.showStatusDisplayName != nil
            || !details.genres.isEmpty

        if hasMetadata {
            VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    if let rating = details.rating {
                        VStack(spacing: 4) {
                            HStack(spacing: 3) {
                                if let ratingCount = details.ratingCount {
                                    Text(ratingCount, format: .number.notation(.compactName))
                                }
                                Text("RATINGS")
                            }
                            .font(.caption.bold())

                            Text(String(format: "%.1f", rating / 2))
                                .font(.title3.bold())
                                .fontDesign(.rounded)
                                .monospacedDigit()

                            RatingBadge(rating: rating / 2)
                                .font(.caption)
                        }
                        .foregroundStyle(.gray)

                        if details.releaseDate != nil
                            || details.movieRuntimeMinutes != nil
                            || details.showStatusDisplayName != nil
                            || !details.genres.isEmpty {
                            metricDivider
                        }
                    }

                    if let releaseDate = details.releaseDate {
                        metric(title: "RELEASE",
                               value: releaseDate.formatted(.dateTime.year()),
                               caption: releaseDate.formatted(.dateTime.month(.abbreviated).day()))
                        if details.movieRuntimeMinutes != nil
                            || details.showStatusDisplayName != nil
                            || !details.genres.isEmpty {
                            metricDivider
                        }
                    }

                    if let runtime = details.movieRuntimeMinutes {
                        metric(title: "RUNTIME", value: "\(runtime)", caption: "Minutes")
                        if !details.genres.isEmpty {
                            metricDivider
                        }
                    }

                    if let status = details.showStatusDisplayName {
                        metric(title: "STATUS", value: status, caption: "Series")
                        if !details.genres.isEmpty {
                            metricDivider
                        }
                    }

                    if !details.genres.isEmpty {
                        let genres = details.genres
                        let primary = genres.first ?? ""
                        let secondary = genres.dropFirst().first ?? ""
                        let remaining = max(0, genres.count - 2)
                        metric(
                            title: "GENRE",
                            value: primary,
                            caption: secondary.isEmpty
                                ? "—"
                                : remaining > 0 ? "\(secondary) + \(remaining) more" : secondary
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            Divider()
                .padding(.horizontal, 14)
            }
        }
    }

    @ViewBuilder
    private func overviewSection(_ details: MediaDetails) -> some View {
        if let overview = details.overview, !overview.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Overview")
                    .font(.title3.bold())

                Text(overview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(model.overviewExpanded ? nil : 3)
                    .truncationMode(.tail)
                    .overlay(alignment: .topLeading) {
                        Text(overview)
                            .font(.callout)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .onNumberOfLinesChange { overviewFullLines = $0 }
                            .opacity(0)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !model.overviewExpanded, overviewFullLines > 3 {
                            let lineHeight = UIFont.preferredFont(forTextStyle: .callout).lineHeight
                            HStack(spacing: 0) {
                                LinearGradient(
                                    colors: [.clear, Color(.systemBackground)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 75, height: lineHeight)
                                .allowsHitTesting(false)

                                Button("more") {
                                    withAnimation(.snappy) {
                                        model.overviewExpanded = true
                                    }
                                }
                                .font(.caption.bold())
                                .background(Color(.systemBackground).frame(height: lineHeight))
                            }
                        }
                    }

                if model.overviewExpanded {
                    Button("less") {
                        withAnimation(.snappy) {
                            model.overviewExpanded = false
                        }
                    }
                    .font(.caption.bold())
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func seasonsSection(_ details: MediaDetails) -> some View {
        if case let .show(show) = details {
            let seasons = show.seasons
                .filter { $0.seasonNumber >= 0 }
                .sorted(by: seasonSort)

            if !seasons.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Seasons")
                        .font(.title3.bold())
                        .padding(.horizontal, 20)

                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(seasons) { season in
                                    Button {
                                        model.toggleSeason(season.seasonNumber)
                                        if model.expandedSeason == season.seasonNumber {
                                            Task { await model.loadSeason(season.seasonNumber) }
                                        }
                                    } label: {
                                        VStack(spacing: 8) {
                                            PosterImage(path: season.posterPath)

                                        Text(displayTitle(for: season))
                                            .font(.headline)
                                                .lineLimit(1)

                                            if let episodeCount = season.episodeCount {
                                                Text("\(episodeCount) episodes")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            }

                                            if model.expandedSeason == season.seasonNumber {
                                                Capsule()
                                                    .fill(Color.accentColor)
                                                    .frame(width: 28, height: 3)
                                                    .matchedGeometryEffect(
                                                        id: "seasonIndicator",
                                                        in: seasonIndicatorNamespace
                                                    )
                                            } else {
                                                Color.clear.frame(height: 3)
                                            }
                                        }
                                        .frame(width: 110)
                                        .padding(.top, 2)
                                    }
                                    .buttonStyle(.plain)
                                    .id(season.seasonNumber)
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.horizontal)
                        }
                        .scrollTargetBehavior(.viewAligned)
                        .onChange(of: model.expandedSeason) { _, seasonNumber in
                            if let seasonNumber {
                                withAnimation(.snappy) {
                                    proxy.scrollTo(seasonNumber, anchor: .center)
                                }
                            }
                        }
                    }

                    if let seasonNumber = model.expandedSeason,
                       seasons.contains(where: { $0.seasonNumber == seasonNumber }) {
                        Divider()
                            .padding(.horizontal, 20)

                        VStack(alignment: .leading, spacing: 8) {
                            if let episodes = model.episodesBySeason[seasonNumber], !episodes.isEmpty {
                                ForEach(episodes) { episode in
                                    episodeRow(episode)
                                }
                            } else {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Loading episodes…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .task {
                                    await model.loadSeason(seasonNumber)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private func episodeRow(_ episode: EpisodeDetails) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                NavigationLink {
                    EpisodeView(ref: episode.ref)
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        EpisodeStillImage(path: episode.stillPath)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("E\(episode.episodeNumber) • \(episode.name)")
                                .font(.headline)

                            if let airDate = episode.airDate {
                                Text(airDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let airDate = episode.airDate, airDate > Date() {
                    releaseCountdown(for: airDate)
                } else {
                    Button {
                        Haptics.notification(.success)
                        Task { await model.toggleEpisodeWatched(episode) }
                    } label: {
                        Image(systemName: "checkmark")
                            .bold()
                            .foregroundStyle(model.isEpisodeWatched(episode) ? Color.white : Color.clear)
                            .imageScale(.small)
                    }
                    .buttonStyle(.borderedProminent)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .clipShape(.circle)
                    .tint(model.isEpisodeWatched(episode) ? Color.accentColor : Color.clear)
                    .overlay {
                        Circle()
                            .strokeBorder(
                                model.isEpisodeWatched(episode) ? Color.accentColor : Color.secondary,
                                lineWidth: 2
                            )
                    }
                }
            }

            Divider()
                .padding(.leading, 130)
        }
    }

    @ViewBuilder
    private func releaseCountdown(for date: Date) -> some View {
        let now = Date()
        if date > now {
            let calendar = Calendar.current
            let dayCount = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: now),
                to: calendar.startOfDay(for: date)
            ).day ?? 0

            if dayCount >= 1 {
                countdown(value: dayCount, unit: dayCount == 1 ? "day" : "days")
            } else {
                let hourCount = max(1, calendar.dateComponents([.hour], from: now, to: date).hour ?? 0)
                countdown(value: hourCount, unit: hourCount == 1 ? "hour" : "hours")
            }
        }
    }

    private func countdown(value: Int, unit: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline.weight(.semibold))
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 34)
    }

    private var metricDivider: some View {
        Divider()
            .frame(height: 42)
            .padding(.horizontal, 12)
    }

    private func metric(title: String, value: String, caption: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .fontDesign(.rounded)
                .lineLimit(1)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func displayTitle(for season: ShowDetails.Season) -> String {
        if !season.name.isEmpty {
            return season.name
        }
        return season.seasonNumber == 0 ? "Specials" : "Season \(season.seasonNumber)"
    }

    private func seasonSort(_ lhs: ShowDetails.Season, _ rhs: ShowDetails.Season) -> Bool {
        switch (lhs.seasonNumber, rhs.seasonNumber) {
        case (0, 0):
            return lhs.id < rhs.id
        case (0, _):
            return false
        case (_, 0):
            return true
        default:
            return lhs.seasonNumber < rhs.seasonNumber
        }
    }
}

#Preview {
    let container = AppContainer.preview()
    NavigationStack {
        MediaDetailView(ref: MediaID(kind: .show, id: 1399))
    }
    .environment(container)
    .environment(container.session)
    .environment(container.router)
    .modelContainer(container.persistence.modelContainer)
}
