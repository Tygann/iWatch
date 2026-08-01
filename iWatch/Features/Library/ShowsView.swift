import SwiftUI
import Observation
import SwiftData

@MainActor
@Observable
private final class ShowsScreenModel {
    private let repository: LibraryRepository
    private let session: AppSession

    var snapshot = ShowLibrarySnapshot.empty
    var isLoading = false
    var isEnriching = false
    var errorText: String?
    private var loadedRevision: Int?
    private var enrichedRevision: Int?

    init(repository: LibraryRepository, session: AppSession) {
        self.repository = repository
        self.session = session
    }

    func load(revision: Int, forceRefresh: Bool = false) async {
        guard forceRefresh || loadedRevision != revision else { return }
        let shouldShowLoading = snapshot.all.isEmpty
        if shouldShowLoading { isLoading = true }
        defer { isLoading = false }

        do {
            snapshot = try await repository.showLibrarySnapshot(
                revision: revision,
                forceRefresh: forceRefresh
            )
            loadedRevision = revision
            errorText = nil
        } catch {
            guard !error.isCancelled else { return }
            snapshot = .empty
            errorText = error.localizedDescription
        }
    }

    func enrichLibrary() async {
        let revision = session.libraryRevision
        guard !isEnriching, enrichedRevision != revision else { return }
        isEnriching = true
        defer {
            isEnriching = false
            if !Task.isCancelled {
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

        if !missingMetadata.isEmpty {
            await load(revision: session.libraryRevision, forceRefresh: true)
        }

        // Episode progress is enriched when a show/season is opened or during sync.
        // Doing it for every followed show here blocks the main actor while SwiftData
        // materializes large episode tables, making the first Shows navigation hang.
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

    func markNextEpisodeWatched(for item: LibraryShowItem) async {
        guard let next = item.progress.nextEpisode else { return }
        do {
            try await repository.addWatchEvent(
                for: MediaID(kind: .episode, id: next.tmdbID, traktID: next.traktID),
                watchedAt: Date()
            )
            session.markLibraryUpdated(syncIfConnected: true)
            await load(revision: session.libraryRevision)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct ShowsView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AppSession.self) private var session

    @State private var model: ShowsScreenModel?
    @State private var showSettings = false
    @State private var detailRef: MediaID?
    @State private var episodeRef: EpisodeRef?

    var body: some View {
        Group {
            if let model {
                ShowsViewBody(
                    model: model,
                    detailRef: $detailRef,
                    episodeRef: $episodeRef,
                    showSettings: $showSettings
                )
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

private struct ShowsViewBody: View {
    @Bindable var model: ShowsScreenModel
    @Binding var detailRef: MediaID?
    @Binding var episodeRef: EpisodeRef?
    @Binding var showSettings: Bool
    @Environment(AppSession.self) private var session

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorText = model.errorText {
                    ContentUnavailableView("Shows Error",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(errorText))
                } else if model.snapshot.all.isEmpty {
                    ContentUnavailableView(
                        "No shows yet",
                        systemImage: "tv",
                        description: Text("Add shows to your Watchlist from Search.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
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
                    Button { showSettings = true } label: {
                        Image(systemName: "person.crop.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.primary, .clear)
                            .scaleEffect(1.5)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .task(id: session.libraryRevision) {
                await model.load(revision: session.libraryRevision)
                await model.enrichLibrary()
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
            .sheet(item: $detailRef) { ref in
                NavigationStack {
                    MediaDetailView(ref: ref)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(role: .close) { detailRef = nil }
                            }
                        }
                }
            }
            .sheet(item: $episodeRef) { ref in
                NavigationStack {
                    EpisodeView(ref: ref)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(role: .close) { episodeRef = nil }
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
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
                    let next = item.progress.nextEpisode
                    MediaTile(
                        ref: item.mediaID,
                        title: item.title,
                        posterPath: item.posterPath,
                        showTitle: false,
                        selectedRef: $detailRef,
                        onSelect: {
                            episodeRef = next.map {
                                EpisodeRef(
                                    showId: item.mediaID.tmdbID,
                                    showTraktID: item.mediaID.traktID,
                                    season: $0.season,
                                    episode: $0.episode,
                                    tmdbID: $0.tmdbID,
                                    traktID: $0.traktID
                                )
                            }
                        },
                        extraMenu: {
                            Button { detailRef = item.mediaID } label: {
                                Label("View Show", systemImage: "tv")
                            }
                            if item.progress.nextEpisode != nil {
                                Button {
                                    Haptics.notification(.success)
                                    Task { await model.markNextEpisodeWatched(for: item) }
                                } label: {
                                    Label("Mark as Watched", systemImage: "rectangle.badge.checkmark")
                                }
                            }
                        }
                    )
                    .accessibilityLabel(
                        next.map { "\(item.title), Season \($0.season) Episode \($0.episode), Continue Watching" }
                            ?? item.title
                    )
                    .overlay(alignment: .topLeading) {
                        if let next = model.nextEpisodeLabel(for: item) {
                            Text(next)
                                .font(.caption2.bold())
                                .padding(3)
                                .glassEffect()
                                .padding(3)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if item.progress.remainingReleased > 0 {
                            SystemBadge(label: "\(item.progress.remainingReleased)", color: .red, height: 20)
                                .offset(x: 8, y: -8)
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
                    detailRef: $detailRef,
                    secondaryText: model.nextAirLabel
                )
            } content: {
                ForEach(model.snapshot.comingUp) { item in
                    VStack(spacing: 6) {
                        MediaTile(
                            ref: item.mediaID,
                            title: item.title,
                            posterPath: item.posterPath,
                            showTitle: false,
                            selectedRef: $detailRef
                        )

                        if let label = model.nextAirLabel(for: item) {
                            Text(label)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
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
                ShowCollectionView(title: title, items: items, detailRef: $detailRef)
            } content: {
                ForEach(items) { item in
                    MediaTile(
                        ref: item.mediaID,
                        title: item.title,
                        posterPath: item.posterPath,
                        showTitle: false,
                        selectedRef: $detailRef
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
                    items: model.snapshot.completed,
                    detailRef: $detailRef
                )
            } content: {
                ForEach(model.snapshot.completed) { item in
                    MediaTile(
                        ref: item.mediaID,
                        title: item.title,
                        posterPath: item.posterPath,
                        showTitle: false,
                        selectedRef: $detailRef
                    )
                    .frame(width: 110)
                }
            }
            .padding(.bottom, 12)
        }
    }
}

private struct ShowCollectionView: View {
    let title: String
    let items: [LibraryShowItem]
    @Binding var detailRef: MediaID?
    let secondaryText: (LibraryShowItem) -> String?

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    init(
        title: String,
        items: [LibraryShowItem],
        detailRef: Binding<MediaID?>,
        secondaryText: @escaping (LibraryShowItem) -> String? = { _ in nil }
    ) {
        self.title = title
        self.items = items
        self._detailRef = detailRef
        self.secondaryText = secondaryText
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(items) { item in
                    VStack(spacing: 6) {
                        MediaTile(
                            ref: item.mediaID,
                            title: item.title,
                            posterPath: item.posterPath,
                            showTitle: true,
                            selectedRef: $detailRef
                        )

                        if let text = secondaryText(item) {
                            Text(text)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
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

#Preview {
    let container = AppContainer.preview()
    ShowsView()
        .environment(container)
        .environment(container.session)
        .environment(container.router)
        .modelContainer(container.persistence.modelContainer)
}
