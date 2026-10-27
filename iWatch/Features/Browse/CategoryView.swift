import Observation
import SwiftUI
import SwiftData

// MARK: - Category State

@MainActor
@Observable
private final class BrowseCategoryModel {
    struct Section: Identifiable {
        let collection: DiscoveryCollection
        var items: [SearchItem] = []
        var isLoading = true
        var errorText: String?

        var id: DiscoveryCollection { collection }
    }

    private let repository: LibraryRepository
    private let kind: MediaKind

    var sections: [Section]

    init(kind: MediaKind, repository: LibraryRepository) {
        self.kind = kind
        self.repository = repository
        sections = DiscoveryCollection.collections(for: kind).map {
            Section(collection: $0, items: [], isLoading: true, errorText: nil)
        }
    }

    func load() async {
        await withTaskGroup(of: (DiscoveryCollection, Result<[SearchItem], Error>).self) { group in
            for collection in sections.map(\.collection) {
                group.addTask { [repository, kind] in
                    do {
                        return (collection, .success(try await repository.discovery(kind: kind, collection: collection)))
                    } catch {
                        return (collection, .failure(error))
                    }
                }
            }

            for await (collection, result) in group {
                guard let index = sections.firstIndex(where: { $0.collection == collection }) else { continue }
                sections[index].isLoading = false
                switch result {
                case .success(let items):
                    sections[index].items = items
                    sections[index].errorText = nil
                case .failure(let error):
                    guard !error.isCancelled else { continue }
                    sections[index].items = []
                    sections[index].errorText = UserFacingError.message(for: error)
                }
            }
        }
    }
}

// MARK: - Category Screen

struct BrowseCategoryView: View {
    let kind: MediaKind

    @Environment(AppContainer.self) private var container
    @State private var model: BrowseCategoryModel?

    private var title: String { kind == .movie ? "Movies" : "Shows" }

    var body: some View {
        Group {
            if let model {
                BrowseCategoryBody(model: model, kind: kind, title: title)
            } else {
                ProgressView()
                    .task {
                        let newModel = BrowseCategoryModel(kind: kind, repository: container.libraryRepository)
                        await newModel.load()
                        guard !Task.isCancelled else { return }
                        model = newModel
                    }
            }
        }
    }
}

// MARK: - Category Content

private struct BrowseCategoryBody: View {
    @Bindable var model: BrowseCategoryModel
    let kind: MediaKind
    let title: String

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(model.sections) { section in
                    DiscoverySectionView(section: section, kind: kind)
                }
            }
            .padding(.bottom, 24)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Discovery Components

private struct DiscoverySectionView: View {
    let section: BrowseCategoryModel.Section
    let kind: MediaKind

    var body: some View {
        if section.isLoading {
            VStack(alignment: .leading, spacing: 12) {
                Text(section.collection.title(for: kind))
                    .font(.title3.bold())
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
            }
            .padding(.horizontal)
        } else if !section.items.isEmpty {
            MediaCollectionRow(title: section.collection.title(for: kind)) {
                SearchCollectionView(title: section.collection.title(for: kind), items: section.items)
            } content: {
                ForEach(section.items) { item in
                    MediaTile(ref: item.mediaID, title: item.title, posterPath: item.posterPath, showTitle: true)
                        .frame(width: 110)
                }
            }
        } else if section.errorText != nil {
            Label("Unable to load \(section.collection.title(for: kind).lowercased())", systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 12)
        }
    }
}

// MARK: - Previews

#Preview("Movies") {
    CategoryPreview(kind: .movie)
}

#Preview("Shows") {
    CategoryPreview(kind: .show)
}

// MARK: - Preview Support

private enum CategoryPreviewFixtures {
    static func model(kind: MediaKind, repository: LibraryRepository) -> BrowseCategoryModel {
        let model = BrowseCategoryModel(kind: kind, repository: repository)
        model.sections = DiscoveryCollection.collections(for: kind).map { collection in
            BrowseCategoryModel.Section(
                collection: collection,
                items: items(for: kind),
                isLoading: false,
                errorText: nil
            )
        }
        return model
    }

    private static func items(for kind: MediaKind) -> [SearchItem] {
        let noun = kind == .movie ? "Movie" : "Show"
        return [
            SearchItem(id: 201, kind: kind, title: "Featured \(noun)", posterPath: nil, year: "2025"),
            SearchItem(id: 202, kind: kind, title: "Popular \(noun)", posterPath: nil, year: "2024"),
            SearchItem(id: 203, kind: kind, title: "Classic \(noun)", posterPath: nil, year: "2020")
        ]
    }
}

private struct CategoryPreview: View {
    private let kind: MediaKind
    private let container: AppContainer
    @State private var model: BrowseCategoryModel

    init(kind: MediaKind) {
        let container = AppContainer.preview()
        self.kind = kind
        self.container = container
        _model = State(initialValue: CategoryPreviewFixtures.model(
            kind: kind,
            repository: container.libraryRepository
        ))
    }

    var body: some View {
        NavigationStack {
            BrowseCategoryBody(
                model: model,
                kind: kind,
                title: kind == .movie ? "Movies" : "Shows"
            )
        }
        .environment(container)
        .environment(container.session)
        .environment(container.router)
        .modelContainer(container.persistence.modelContainer)
    }
}
