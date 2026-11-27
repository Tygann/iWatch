import SwiftUI
import Observation
import SwiftData

// MARK: - Shows State

@MainActor
@Observable
final class ShowsScreenModel {
    private let repository: LibraryRepository
    private let session: AppSession
    private let loadSnapshot: @MainActor (Int, Bool) async throws -> ShowLibrarySnapshot

    var snapshot = ShowLibrarySnapshot.empty
    var isShowingSavedSnapshot = false
    var isLoading = false
    var isEnriching = false
    var errorText: String?
    private var loadToken: UUID?
    private(set) var markingShowIDs: Set<Int> = []
    private var continueWatchingOrder: [Int] = []
    private var loadedRevision: Int?
    private var enrichedRevision: Int?

    init(repository: LibraryRepository, session: AppSession,
         loadSnapshot: (@MainActor (Int, Bool) async throws -> ShowLibrarySnapshot)? = nil) {
        self.repository = repository
        if let saved = repository.savedShowLibrarySnapshot() {
            self.snapshot = saved
            self.continueWatchingOrder = saved.continueWatching.map(\.id)
            self.isShowingSavedSnapshot = true
        }
        self.session = session
        self.loadSnapshot = loadSnapshot ?? { revision, force in
            try await repository.showLibrarySnapshot(revision: revision, forceRefresh: force)
        }
    }

    func load(revision: Int, forceRefresh: Bool = false) async {
        guard forceRefresh || loadedRevision != revision else { return }
        let token = UUID()
        loadToken = token
        let shouldShowLoading = snapshot.all.isEmpty
        if shouldShowLoading { isLoading = true }
        defer {
            if loadToken == token { isLoading = false }
        }

        do {
            let loaded = try await loadSnapshot(revision, forceRefresh)
            try Task.checkCancellation()
            guard loadToken == token else { return }
            for item in snapshot.continueWatching + loaded.continueWatching where !continueWatchingOrder.contains(item.id) {
                continueWatchingOrder.append(item.id)
            }
            snapshot = loaded
            isShowingSavedSnapshot = false
            loadedRevision = revision
            errorText = nil
        } catch {
            guard loadToken == token, !error.isCancelled else { return }
            errorText = UserFacingError.message(for: error, context: .library)
        }
    }

    func enrichLibrary() async {
        let revision = session.libraryRevision
        guard !isEnriching, enrichedRevision != revision else { return }
        isEnriching = true
        var hadEnrichmentFailure = false
        defer {
            isEnriching = false
            if !Task.isCancelled, !hadEnrichmentFailure {
                enrichedRevision = revision
            }
        }

        let missingMetadata = snapshot.all.filter { $0.posterPath == nil }
        for item in missingMetadata {
            guard !Task.isCancelled else { return }
            do {
                try await repository.enrichMetadata(for: item.mediaID)
            } catch {
                guard !error.isCancelled else { return }
                // Keep rendering imported Trakt data when optional metadata is unavailable.
            }
        }

        var enrichedAirtimes = false
        for item in snapshot.all {
            guard !Task.isCancelled else { return }
            enrichedAirtimes = await repository.enrichUpcomingEpisodeAirtimes(for: item.mediaID)
                || enrichedAirtimes
        }

        if !missingMetadata.isEmpty || enrichedAirtimes {
            await load(revision: session.libraryRevision, forceRefresh: true)
        }

        // Publish the initial library first, then fill missing catalogs incrementally.
        // Recently watched shows are most likely to have a next episode to surface.
        let missingProgress = snapshot.all
            .filter { $0.disposition == .active && $0.needsProgressEnrichment }
            .sorted { ($0.lastWatchedAt ?? .distantPast) > ($1.lastWatchedAt ?? .distantPast) }
        var needsSnapshot = false
        for (index, item) in missingProgress.enumerated() {
            guard !Task.isCancelled else { return }
            do {
                try await repository.enrichShowProgress(for: item.mediaID)
                needsSnapshot = true
            } catch {
                guard !error.isCancelled else { return }
                hadEnrichmentFailure = true
            }
            if index == 0, needsSnapshot {
                await load(revision: session.libraryRevision, forceRefresh: true)
                needsSnapshot = false
            }
        }
        if needsSnapshot {
            await load(revision: session.libraryRevision, forceRefresh: true)
        }
        if hadEnrichmentFailure { enrichedRevision = nil }
    }

    var continueWatchingItems: [LibraryShowItem] {
        snapshot.continueWatching.sorted {
            (continueWatchingOrder.firstIndex(of: $0.id) ?? .max) <
            (continueWatchingOrder.firstIndex(of: $1.id) ?? .max)
        }
    }

    func nextEpisodeLabel(for item: LibraryShowItem) -> String? {
        guard let next = item.progress.nextEpisode else { return nil }
        return "S\(next.season) E\(next.episode)"
    }

    func nextAirLabel(for item: LibraryShowItem) -> String? {
        guard let date = item.status.nextAirDate else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: Date()),
                                      to: cal.startOfDay(for: date)).day ?? 0
        guard days >= 0 else { return nil }
        if days == 0 { return "Today" }
        if days == 1 { return "1 day" }
        return "\(days) days"
    }

    func markNextEpisodeWatched(
        for item: LibraryShowItem, showsFeedback: Bool = false, onSaved: () -> Void = {}
    ) async {
        guard let next = item.progress.nextEpisode,
              markingShowIDs.insert(item.id).inserted else { return }
        defer { markingShowIDs.remove(item.id) }
        do {
            let eventID = try await repository.addWatchEvent(
                for: MediaID(kind: .episode, id: next.tmdbID, traktID: next.traktID),
                watchedAt: Date(), allowRewatch: false
            )
            if eventID != nil { onSaved() }
            if showsFeedback, let eventID {
                session.showEpisodeWatchSuccess(showTitle: item.title, season: next.season,
                    episode: next.episode, undo: { [self] in
                        do {
                            try await repository.removeWatchEvent(eventID: eventID)
                            session.markLibraryUpdated(syncIfConnected: true)
                            await load(revision: session.libraryRevision)
                        } catch {
                            errorText = UserFacingError.message(for: error, context: .action)
                        }
                    })
            }
            session.markLibraryUpdated(syncIfConnected: true)
            let revision = session.libraryRevision
            let updated = try? await repository.showLibraryItem(for: item.id)
            guard session.libraryRevision == revision, loadedRevision != revision else { return }
            if let updated {
                snapshot = ShowLibrarySnapshot(items: snapshot.all.map { $0.id == updated.id ? updated : $0 })
            } else {
                await load(revision: revision)
            }
        } catch {
            errorText = UserFacingError.message(for: error, context: .action)
        }
    }

    func stopWatching(_ item: LibraryShowItem) async {
        do {
            try await repository.setShowDisposition(.stopped, for: item.mediaID)
            session.markLibraryUpdated(syncIfConnected: true)
            await load(revision: session.libraryRevision)
        } catch {
            errorText = UserFacingError.message(for: error, context: .action)
        }
    }
}

// MARK: - Shows Screen

struct ShowsView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AppSession.self) private var session

    @State private var model: ShowsScreenModel?

    var body: some View {
        Group {
            if let model {
                ShowsViewBody(model: model)
            } else {
                ProgressView()
                    .task {
                        let newModel = ShowsScreenModel(repository: container.libraryRepository, session: session)
                        model = newModel
                    }
            }
        }
    }
}

// MARK: - Shows Content

private struct ShowsViewBody: View {
    @Bindable var model: ShowsScreenModel
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.snapshot.all.isEmpty, let errorText = model.errorText {
                    RetryUnavailableView(title: "Unable to Load Shows", message: errorText) {
                        Task { await model.load(revision: session.libraryRevision, forceRefresh: true) }
                    }
                } else if model.snapshot.all.isEmpty {
                    ContentUnavailableView(
                        "No shows yet",
                        systemImage: "tv",
                        description: Text("Add shows to your Watchlist from Search.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        if let errorText = model.errorText {
                            RecoveryNotice(message: errorText) {
                                Task { await model.load(revision: session.libraryRevision, forceRefresh: true) }
                            }
                        }
                        continueWatchingEpisodeSection
                        comingUpSection
                        librarySection(title: "Not Started", items: model.snapshot.watchlist)
                        librarySection(title: "Caught Up", items: model.snapshot.caughtUp)
                        completedSection
                    }
                }
            }
            .navigationTitle("Shows")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { router.isShowingSettings = true } label: {
                        Image(systemName: "person.crop.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.primary, .clear)
                            .scaleEffect(1.5)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .task(id: session.libraryRevision) {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("UITEST_MODE"),
                   ProcessInfo.processInfo.arguments.contains("UITEST_DELAY_LIBRARY_REFRESH") {
                    do { try await Task.sleep(for: .seconds(4)) } catch { return }
                }
                #endif
                await model.load(revision: session.libraryRevision)
                await model.enrichLibrary()
            }
        }
    }

    @ViewBuilder
    // MARK: Library Sections

    private var continueWatchingEpisodeSection: some View {
        if !model.snapshot.continueWatching.isEmpty {
            MediaCollectionRow(title: "Continue Watching", alignment: .top) {
                WatchlistView(
                    kind: .show,
                    initialShowItems: model.continueWatchingItems,
                    initialRevision: model.isShowingSavedSnapshot ? nil : session.libraryRevision
                )
            } content: {
                ForEach(model.continueWatchingItems) { item in
                    ContinueWatchingCard(item: item, isWorking: model.markingShowIDs.contains(item.id)) {
                        continueWatchingMenu(for: item)
                    } markWatched: { onSaved in
                        await model.markNextEpisodeWatched(for: item, showsFeedback: true, onSaved: onSaved)
                    }
                }
            }
        }
    }

    // Retained for future use as an alternate poster row.
    @ViewBuilder
    private var continueWatchingSection: some View {
        if !model.snapshot.continueWatching.isEmpty {
            MediaCollectionRow(title: "Continue Watching") {
                WatchlistView(
                    kind: .show,
                    initialShowItems: model.continueWatchingItems,
                    initialRevision: model.isShowingSavedSnapshot ? nil : session.libraryRevision
                )
            } content: {
                ForEach(model.continueWatchingItems) { item in
                    continueWatchingTile(item)
                    .accessibilityLabel(
                        item.progress.nextEpisode.map { "\(item.title), Season \($0.season) Episode \($0.episode), Continue Watching" }
                            ?? item.title
                    )
                    .overlay(alignment: .topLeading) {
                        if let next = model.nextEpisodeLabel(for: item) {
                            Text(next)
                                .font(.caption2.bold())
                                .padding(3)
                                .glassEffect()
                                .padding(3)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if item.progress.remainingReleased > 0 {
                            SystemBadge(label: "\(item.progress.remainingReleased)", color: .red, height: 20)
                                .offset(x: 8, y: -8)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: 110)
                    .overlay(alignment: .topTrailing) {
                        if let next = item.progress.nextEpisode {
                            QuickEpisodeWatchButton(showTitle: item.title, season: next.season,
                                episode: next.episode, isWorking: model.markingShowIDs.contains(item.id)) { onSaved in
                                    await model.markNextEpisodeWatched(for: item, showsFeedback: true, onSaved: onSaved)
                                }
                                .padding(.top, 110 / PosterImage.aspectRatio - 44)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var comingUpSection: some View {
        if !model.snapshot.comingUp.isEmpty {
            MediaCollectionRow(title: "Coming Up") {
                ShowCollectionView(
                    title: "Coming Up",
                    items: model.snapshot.comingUp,
                    secondaryText: model.nextAirLabel
                )
            } content: {
                ForEach(model.snapshot.comingUp) { item in
//                    VStack(spacing: 6) {
                        MediaTile(
                            ref: item.mediaID,
                            title: item.title,
                            posterPath: item.posterPath,
                            showTitle: false,
                            showsWatchlistAction: false
                        )

//                        if let label = model.nextAirLabel(for: item) {
//                            Text(label)
//                                .font(.footnote.weight(.semibold))
//                                .lineLimit(1)
//                                .minimumScaleFactor(0.7)
//                                .frame(maxWidth: .infinity)
//                                .multilineTextAlignment(.center)
//                        }
//                    }
                    .overlay(alignment: .topLeading) {
                        if let label = model.nextAirLabel(for: item) {
                            Text(label)
                                .font(.caption2.bold())
                                .padding(3)
                                .glassEffect()
                                .padding(3)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: 110)
                }
            }
        }
    }

    @ViewBuilder
    private func librarySection(title: String, items: [LibraryShowItem]) -> some View {
        if !items.isEmpty {
            MediaCollectionRow(title: title) {
                ShowCollectionView(title: title, items: items)
            } content: {
                ForEach(items) { item in
                    MediaTile(
                        ref: item.mediaID,
                        title: item.title,
                        posterPath: item.posterPath,
                        showTitle: false,
                        showsWatchlistAction: title == "Not Started"
                    )
                    .frame(width: 110)
                }
            }
        }
    }

    @ViewBuilder
    private var completedSection: some View {
        if !model.snapshot.completed.isEmpty {
            MediaCollectionRow(title: "Completed") {
                ShowCollectionView(
                    title: "Completed",
                    items: model.snapshot.completed
                )
            } content: {
                ForEach(model.snapshot.completed) { item in
                    MediaTile(
                        ref: item.mediaID,
                        title: item.title,
                        posterPath: item.posterPath,
                        showTitle: false,
                        showsWatchlistAction: false
                    )
                    .frame(width: 110)
                }
            }
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func continueWatchingTile(_ item: LibraryShowItem) -> some View {
        if let next = item.progress.nextEpisode {
            let episodeRef = EpisodeRef(
                showId: item.mediaID.tmdbID,
                showTraktID: item.mediaID.traktID,
                season: next.season,
                episode: next.episode,
                tmdbID: next.tmdbID,
                traktID: next.traktID
            )

            MediaTile(
                ref: item.mediaID,
                title: item.title,
                posterPath: item.posterPath,
                showTitle: false,
                showsWatchlistAction: false,
                transitionID: .episode(episodeRef),
                destination: { EpisodeView(ref: episodeRef) },
                extraMenu: { continueWatchingMenu(for: item) }
            )
        } else {
            MediaTile(
                ref: item.mediaID,
                title: item.title,
                posterPath: item.posterPath,
                showTitle: false,
                showsWatchlistAction: false,
                extraMenu: { continueWatchingMenu(for: item) }
            )
        }
    }

    @ViewBuilder
    private func continueWatchingMenu(for item: LibraryShowItem) -> some View {
        if item.progress.nextEpisode != nil {
            NavigationLink {
                MediaDetailView(ref: item.mediaID)
            } label: {
                Label("Go to Show", systemImage: "info.circle")
            }
            Divider()
            Button {
                Task { await model.markNextEpisodeWatched(for: item, showsFeedback: true) }
            } label: {
                Label("Mark as Watched", systemImage: "checkmark.circle")
            }
        }
        Button {
            Haptics.notification(.success)
            Task { await model.stopWatching(item) }
        } label: {
            Label("Stop Watching", systemImage: "stop.circle")
        }
    }
}

// MARK: - Collection Screen

private struct ShowCollectionView: View {
    let title: String
    let items: [LibraryShowItem]
    let secondaryText: (LibraryShowItem) -> String?

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    init(
        title: String,
        items: [LibraryShowItem],
        secondaryText: @escaping (LibraryShowItem) -> String? = { _ in nil }
    ) {
        self.title = title
        self.items = items
        self.secondaryText = secondaryText
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(items) { item in
//                    VStack(spacing: 6) {
                        MediaTile(
                            ref: item.mediaID,
                            title: item.title,
                            posterPath: item.posterPath,
                            showTitle: true,
                            showsWatchlistAction: false
                        )

//                        if let text = secondaryText(item) {
//                            Text(text)
//                                .font(.footnote.weight(.semibold))
//                                .lineLimit(1)
//                                .minimumScaleFactor(0.7)
//                                .frame(maxWidth: .infinity)
//                                .multilineTextAlignment(.center)
//                        }
//                    }
                    .overlay(alignment: .topLeading) {
                        if let text = secondaryText(item) {
                            Text(text)
                                .font(.caption2.bold())
                                .padding(3)
                                .glassEffect()
                                .padding(3)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: 110)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

#Preview {
    let container = AppContainer.preview()
    ShowsView()
        .environment(container)
        .environment(container.session)
        .environment(container.router)
        .modelContainer(container.persistence.modelContainer)
}

// Keep the outgoing episode visible briefly while the saved checkmark starts drawing.
private struct ContinueWatchingCard<ExtraMenu: View>: View {
    let item: LibraryShowItem
    let isWorking: Bool
    @ViewBuilder let extraMenu: () -> ExtraMenu
    let markWatched: (@escaping () -> Void) async -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmedItem: LibraryShowItem?

    var body: some View {
        let displayed = confirmedItem ?? item
        if let next = displayed.progress.nextEpisode {
            ContinueWatchingEpisodeTile(
                showTitle: displayed.title,
                episodeName: next.name,
                episodeRef: EpisodeRef(
                    showId: displayed.mediaID.tmdbID,
                    showTraktID: displayed.mediaID.traktID,
                    season: next.season,
                    episode: next.episode,
                    tmdbID: next.tmdbID,
                    traktID: next.traktID
                ),
                stillPath: next.stillPath,
                fallbackPosterPath: displayed.posterPath,
                remainingEpisodes: displayed.progress.remainingReleased,
                usesFrostedFooter: false,
                extraMenu: extraMenu
            )
            .accessibilityIdentifier("continue-watching-episode-\(item.id)")
            .disabled(confirmedItem != nil)
            .overlay(alignment: .topTrailing) {
                QuickEpisodeWatchButton(
                    showTitle: displayed.title, season: next.season, episode: next.episode,
                    isWorking: isWorking || confirmedItem != nil,
                    releasedProgress: item.progress.watchedReleasedCount.map {
                        (watched: $0, remaining: item.progress.remainingReleased)
                    }
                ) { onSaved in
                    await markWatched {
                        if !reduceMotion { confirmedItem = displayed }
                        onSaved()
                    }
                }
                .accessibilityIdentifier("episode-preview-watch-\(item.id)")
            }
            .task(id: confirmedItem != nil) {
                guard confirmedItem != nil else { return }
                try? await Task.sleep(for: .milliseconds(175))
                guard !Task.isCancelled else { return }
                confirmedItem = nil
            }
        }
    }
}
