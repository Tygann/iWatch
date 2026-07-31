import SwiftUI
import Observation

@MainActor
@Observable
private final class BrowseCategoryModel {
    private let repository: LibraryRepository
    private let kind: MediaKind

    var trending: [SearchItem] = []
    var isLoading = true
    var errorText: String?

    init(kind: MediaKind, repository: LibraryRepository) {
        self.kind = kind
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            trending = try await repository.trending(kind: kind)
            errorText = nil
        } catch {
            guard !error.isCancelled else { return }
            trending = []
            errorText = error.localizedDescription
        }
    }
}

struct BrowseCategoryView: View {
    let kind: MediaKind

    @Environment(AppContainer.self) private var container
    @State private var model: BrowseCategoryModel?
    @State private var detailRef: MediaID?

    private var title: String { kind == .movie ? "Movies" : "Shows" }

    var body: some View {
        Group {
            if let model {
                BrowseCategoryBody(model: model, title: title, detailRef: $detailRef)
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

private struct BrowseCategoryBody: View {
    @Bindable var model: BrowseCategoryModel
    let title: String
    @Binding var detailRef: MediaID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Trending")
                        .font(.title2.bold())
                        .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(model.trending) { item in
                                MediaTile(
                                    ref: item.mediaID,
                                    title: item.title,
                                    posterPath: item.posterPath,
                                    showTitle: true,
                                    selectedRef: $detailRef
                                )
                                .frame(width: 110)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal)
                    }
                    .scrollTargetBehavior(.viewAligned)
                }
            }
            .padding(.top, 12)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if model.isLoading {
                ProgressView().scaleEffect(1.2)
            } else if let errorText = model.errorText {
                ContentUnavailableView("Error",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(errorText))
            } else if model.trending.isEmpty {
                ContentUnavailableView("No \(title)",
                                       systemImage: title == "Movies" ? "film" : "tv",
                                       description: Text("Nothing trending right now."))
            }
        }
    }
}
