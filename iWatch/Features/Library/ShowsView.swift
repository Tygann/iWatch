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

        let progressCandidates = snapshot.all.filter {
            $0.progress.watchedCount > 0 && $0.needsProgressEnrichment
        }
        for item in progressCandidates {
            guard !Task.isCancelled else { return }
            do {
                try await repository.enrichShowProgress(for: item.mediaID)
            } catch {
                guard !error.isCancelled else { return }
                // Continue enriching other shows after an individual metadata failure.
            }
        }
        if !progressCandidates.isEmpty {
            await load(revision: session.libraryRevision, forceRefresh: true)
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
        if days <= 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
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

    var body: some View {
        Group {
            if let model {
                ShowsViewBody(
                    model: model,
                    detailRef: $detailRef,
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
    @Binding var showSettings: Bool
    @Environment(AppSession.self) private var session
    @AppStorage("hideEndedShows") private var hideEndedShows = false

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 12)]

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
                        "No tracked shows yet",
                        systemImage: "tv",
                        description: Text("Add TV shows from Search to start tracking.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        continueWatchingSection
                        statusSection(title: "Airing", bucket: .airing)
                        statusSection(title: "Returning", bucket: .returning)
                        statusSection(title: "Ended", bucket: .ended)
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
        }
    }

    @ViewBuilder
    private var continueWatchingSection: some View {
        if !model.snapshot.continueWatching.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                NavigationLink {
                    WatchlistView(
                        kind: .show,
                        initialShowItems: model.snapshot.continueWatching,
                        initialRevision: session.libraryRevision
                    )
                } label: {
                    Text("Continue Watching")
                        .font(.title3.weight(.bold))
                    Image(systemName: "chevron.right")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading)
                .buttonStyle(.plain)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(model.snapshot.continueWatching) { item in
                            MediaTile(
                                ref: item.mediaID,
                                title: item.title,
                                posterPath: item.posterPath,
                                showTitle: true,
                                selectedRef: $detailRef
                            ) {
                                if item.progress.nextEpisode != nil {
                                    Button {
                                        Haptics.notification(.success)
                                        Task { await model.markNextEpisodeWatched(for: item) }
                                    } label: {
                                        Label("Mark as Watched", systemImage: "rectangle.badge.checkmark")
                                    }
                                }
                            }
                            .overlay(alignment: .topLeading) {
                                if let next = model.nextEpisodeLabel(for: item) {
                                    Text(next)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 3)
                                        .background(.thinMaterial, in: .capsule)
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
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func statusSection(title: String, bucket: ShowStatusSnapshot.Bucket) -> some View {
        let items = model.snapshot.items(in: bucket)
        if !items.isEmpty && !(hideEndedShows && bucket == .ended) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal)
                    .padding(.top, 12)

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

                            if bucket == .airing, let label = model.nextAirLabel(for: item) {
                                Text(label)
                                    .font(.footnote.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(width: 110)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
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
