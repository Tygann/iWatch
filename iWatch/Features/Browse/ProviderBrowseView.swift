import Observation
import SwiftUI
import SwiftData

// MARK: - Provider Browser State

@MainActor
@Observable
private final class ProviderBrowseModel {
    private let repository: LibraryRepository
    let regionCode: String

    var providers: [DiscoveryProvider] = []
    var isLoading = true
    var errorText: String?

    init(repository: LibraryRepository, regionCode: String) {
        self.repository = repository
        self.regionCode = regionCode
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            providers = try await repository.watchProviders(regionCode: regionCode)
            errorText = nil
        } catch {
            guard !error.isCancelled else { return }
            providers = []
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Provider Browser Screen

struct ProviderBrowseView: View {
    @Environment(AppContainer.self) private var container
    @State private var model: ProviderBrowseModel?

    var body: some View {
        Group {
            if let model {
                ProviderBrowseBody(model: model)
            } else {
                ProgressView()
                    .task {
                        let newModel = ProviderBrowseModel(
                            repository: container.libraryRepository,
                            regionCode: Locale.current.region?.identifier ?? "US"
                        )
                        await newModel.load()
                        guard !Task.isCancelled else { return }
                        model = newModel
                    }
            }
        }
        .navigationTitle("Services")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Provider Browser Content

private struct ProviderBrowseBody: View {
    @Bindable var model: ProviderBrowseModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 2 : 4
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    private var providerSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 72 : 64
    }

    var body: some View {
        Group {
            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText = model.errorText {
                ContentUnavailableView("Services Unavailable", systemImage: "wifi.exclamationmark", description: Text(errorText))
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(model.providers) { provider in
                            NavigationLink {
                                ProviderResultsView(provider: provider, regionCode: model.regionCode)
                            } label: {
                                ProviderLogo(provider: provider, size: providerSize)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()

                    Text("Availability for \(Locale.current.localizedString(forRegionCode: model.regionCode) ?? model.regionCode). Provider data by JustWatch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                }
            }
        }
    }
}

// MARK: - Provider Components

struct ProviderLogo: View {
    let provider: DiscoveryProvider
    let size: CGFloat

    var body: some View {
        ServiceProviderTile(
            name: provider.name,
            logoPath: provider.logoPath,
            size: size,
            caption: provider.name,
            captionWeight: .regular
        )
    }
}

// MARK: - Provider Results State

@MainActor
@Observable
private final class ProviderResultsModel {
    private let repository: LibraryRepository
    private let providerID: Int
    private let regionCode: String
    let loadsRemotely: Bool

    var mediaScope: ProviderMediaScope = .all
    var offerType: ProviderOfferType = .stream
    var items: [SearchItem] = []
    var isLoading = true
    var errorText: String?

    init(
        providerID: Int,
        regionCode: String,
        repository: LibraryRepository,
        loadsRemotely: Bool = true
    ) {
        self.providerID = providerID
        self.regionCode = regionCode
        self.repository = repository
        self.loadsRemotely = loadsRemotely
    }

    func load() async {
        let requestedScope = mediaScope
        let requestedOfferType = offerType
        isLoading = true
        errorText = nil

        do {
            let loadedItems: [SearchItem]
            switch requestedScope {
            case .all:
                async let movies = repository.discover(
                    kind: .movie,
                    providerID: providerID,
                    offerType: requestedOfferType,
                    regionCode: regionCode
                )
                async let shows = repository.discover(
                    kind: .show,
                    providerID: providerID,
                    offerType: requestedOfferType,
                    regionCode: regionCode
                )
                loadedItems = try await interleaved(movies, shows)
            case .movies:
                loadedItems = try await repository.discover(
                    kind: .movie,
                    providerID: providerID,
                    offerType: requestedOfferType,
                    regionCode: regionCode
                )
            case .shows:
                loadedItems = try await repository.discover(
                    kind: .show,
                    providerID: providerID,
                    offerType: requestedOfferType,
                    regionCode: regionCode
                )
            }

            guard !Task.isCancelled, requestedScope == mediaScope, requestedOfferType == offerType else { return }
            items = loadedItems
        } catch {
            guard !error.isCancelled else { return }
            guard requestedScope == mediaScope, requestedOfferType == offerType else { return }
            items = []
            errorText = error.localizedDescription
        }
        guard requestedScope == mediaScope, requestedOfferType == offerType else { return }
        isLoading = false
    }

    var filterID: String { "\(mediaScope.rawValue)-\(offerType.rawValue)" }
}

private enum ProviderMediaScope: String, CaseIterable, Identifiable {
    case all
    case movies
    case shows

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private func interleaved(_ movies: [SearchItem], _ shows: [SearchItem]) -> [SearchItem] {
    var items: [SearchItem] = []
    items.reserveCapacity(movies.count + shows.count)

    for index in 0 ..< max(movies.count, shows.count) {
        if movies.indices.contains(index) { items.append(movies[index]) }
        if shows.indices.contains(index) { items.append(shows[index]) }
    }
    return items
}

// MARK: - Provider Results Screen

struct ProviderResultsView: View {
    let provider: DiscoveryProvider
    let regionCode: String

    @Environment(AppContainer.self) private var container
    @State private var model: ProviderResultsModel?

    var body: some View {
        Group {
            if let model {
                ProviderResultsBody(model: model, regionCode: regionCode)
            } else {
                ProgressView().onAppear {
                    model = ProviderResultsModel(
                        providerID: provider.id,
                        regionCode: regionCode,
                        repository: container.libraryRepository
                    )
                }
            }
        }
        .navigationTitle(provider.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Provider Results Content

private struct ProviderResultsBody: View {
    @Bindable var model: ProviderResultsModel
    let regionCode: String
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        Group {
            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText = model.errorText {
                ContentUnavailableView("Titles Unavailable", systemImage: "wifi.exclamationmark", description: Text(errorText))
            } else if model.items.isEmpty {
                ContentUnavailableView("No Titles", systemImage: "play.tv", description: Text("No \(model.offerType.title.lowercased()) titles were found for this service in \(regionCode)."))
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.items, id: \.mediaID) { item in
                            DiscoveryPosterTile(
                                item: item,
                                showTitle: true,
                                showKindBadge: model.mediaScope == .all
                            )
                        }
                    }
                    .padding()

                    Text("Availability for \(regionCode). Provider data by JustWatch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 24)
                }
            }
        }
        .task(id: model.filterID) {
            guard model.loadsRemotely else { return }
            await model.load()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Section("Media Type") {
                        Picker("Media Type", selection: $model.mediaScope) {
                            ForEach(ProviderMediaScope.allCases) { scope in
                                Text(scope.title).tag(scope)
                            }
                        }
                    }

                    Section("Availability") {
                        Picker("Availability", selection: $model.offerType) {
                            ForEach(ProviderOfferType.allCases) { offerType in
                                Text(offerType.title).tag(offerType)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .accessibilityLabel("Filters")
                .accessibilityValue("\(model.mediaScope.title), \(model.offerType.title)")
            }
        }
    }
}

// MARK: - Previews

#Preview("Services") {
    ProviderBrowserPreview()
}

#Preview("Services, Accessibility Text") {
    ProviderBrowserPreview()
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Provider Results") {
    ProviderResultsPreview()
}

// MARK: - Preview Support

private enum ProviderPreviewFixtures {
    static let providers = [
        DiscoveryProvider(id: 8, name: "Netflix", logoPath: nil, displayPriority: 1),
        DiscoveryProvider(id: 350, name: "Apple TV+", logoPath: nil, displayPriority: 2),
        DiscoveryProvider(id: 337, name: "Disney+", logoPath: nil, displayPriority: 3),
        DiscoveryProvider(id: 9, name: "Prime Video", logoPath: nil, displayPriority: 4),
        DiscoveryProvider(id: 15, name: "Hulu", logoPath: nil, displayPriority: 5),
        DiscoveryProvider(id: 1899, name: "Max", logoPath: nil, displayPriority: 6),
        DiscoveryProvider(id: 386, name: "Peacock", logoPath: nil, displayPriority: 7),
        DiscoveryProvider(id: 531, name: "Paramount+", logoPath: nil, displayPriority: 8)
    ]

    static let items = [
        SearchItem(id: 301, kind: .movie, title: "Midnight Signal", posterPath: nil, year: "2025"),
        SearchItem(id: 302, kind: .show, title: "Northern Lights", posterPath: nil, year: "2024"),
        SearchItem(id: 303, kind: .movie, title: "The Long Way Home", posterPath: nil, year: "2023"),
        SearchItem(id: 304, kind: .show, title: "Foundation", posterPath: nil, year: "2021")
    ]
}

private struct ProviderBrowserPreview: View {
    private let container: AppContainer
    @State private var model: ProviderBrowseModel

    init() {
        let container = AppContainer.preview()
        let model = ProviderBrowseModel(repository: container.libraryRepository, regionCode: "US")
        model.providers = ProviderPreviewFixtures.providers
        model.isLoading = false
        self.container = container
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            ProviderBrowseBody(model: model)
                .navigationTitle("Services")
        }
        .environment(container)
        .environment(container.session)
        .environment(container.router)
        .modelContainer(container.persistence.modelContainer)
    }
}

private struct ProviderResultsPreview: View {
    private let container: AppContainer
    private let provider: DiscoveryProvider
    @State private var model: ProviderResultsModel

    init() {
        let container = AppContainer.preview()
        let provider = ProviderPreviewFixtures.providers[0]
        let model = ProviderResultsModel(
            providerID: provider.id,
            regionCode: "US",
            repository: container.libraryRepository,
            loadsRemotely: false
        )
        model.items = ProviderPreviewFixtures.items
        model.isLoading = false
        self.container = container
        self.provider = provider
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            ProviderResultsBody(model: model, regionCode: "US")
                .navigationTitle(provider.name)
        }
        .environment(container)
        .environment(container.session)
        .environment(container.router)
        .modelContainer(container.persistence.modelContainer)
    }
}
