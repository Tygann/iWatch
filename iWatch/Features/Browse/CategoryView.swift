import Observation
import SwiftUI

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
                    sections[index].errorText = error.localizedDescription
                }
            }
        }
    }
}

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
