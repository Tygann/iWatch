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
    var isLoading = false
    var isEnriching = false
    var errorText: String?
    private var loadedRevision: Int?
    private var enrichedRevision: Int?

    init(repository: LibraryRepository, session: AppSession,
         loadSnapshot: (@MainActor (Int, Bool) async throws -> ShowLibrarySnapshot)? = nil) {
        self.repository = repository
        self.session = session
        self.loadSnapshot = loadSnapshot ?? { revision, force in
            try await repository.showLibrarySnapshot(revision: revision, forceRefresh: force)
        }
    }

    func load(revision: Int, forceRefresh: Bool = false) async {
        guard forceRefresh || loadedRevision != revision else { return }
        let shouldShowLoading = snapshot.all.isEmpty
        if shouldShowLoading { isLoading = true }
        defer { isLoading = false }

        do {
            snapshot = try await loadSnapshot(revision, forceRefresh)
            loadedRevision = revision
            errorText = nil
        } catch {
            guard !error.isCancelled else { return }
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
        for item in missingProgress {
            guard !Task.isCancelled else { return }
            do {
                try await repository.enrichShowProgress(for: item.mediaID)
            } catch {
                guard !error.isCancelled else { return }
                hadEnrichmentFailure = true
            }
            await load(revision: session.libraryRevision, forceRefresh: true)
            await Task.yield()
        }
        if hadEnrichmentFailure { enrichedRevision = nil }
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

    func markNextEpisodeWatched(for item: LibraryShowItem, showsFeedback: Bool = false) async {
        guard let next = item.progress.nextEpisode else { return }
        do {
            try await repository.addWatchEvent(
                for: MediaID(kind: .episode, id: next.tmdbID, traktID: next.traktID),
                watchedAt: Date()
            )
            if showsFeedback {
                session.showEpisodeWatchSuccess(
                    showTitle: item.title,
                    season: next.season,
                    episode: next.episode
                )
            }
            session.markLibraryUpdated(syncIfConnected: true)
            await load(revision: session.libraryRevision)
        } catch {
            errorText = UserFacingError.message(for: error, context: .library)
        }
    }

    func stopWatching(_ item: LibraryShowItem) async {
        do {
            try await repository.setShowDisposition(.stopped, for: item.mediaID)
            session.markLibraryUpdated(syncIfConnected: true)
            await load(revision: session.libraryRevision)
        } catch {
            errorText = UserFacingError.message(for: error, context: .library)
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
                        continueWatchingSection
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
                await model.load(revision: session.libraryRevision, forceRefresh: true)
                await model.enrichLibrary()
            }
        }
    }

    @ViewBuilder
    // MARK: Library Sections

    private var continueWatchingSection: some View {
        if !model.snapshot.continueWatching.isEmpty {
            MediaCollectionRow(title: "Continue Watching") {
                WatchlistView(
                    kind: .show,
                    initialShowItems: model.snapshot.continueWatching,
                    initialRevision: session.libraryRevision
                )
            } content: {
                ForEach(model.snapshot.continueWatching) { item in
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
                Haptics.notification(.success)
                Task { await model.markNextEpisodeWatched(for: item) }
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
