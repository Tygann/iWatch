import Observation
import SwiftUI

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

@MainActor
@Observable
private final class ProviderResultsModel {
    private let repository: LibraryRepository
    private let providerID: Int
    private let regionCode: String

    var mediaScope: ProviderMediaScope = .all
    var offerType: ProviderOfferType = .stream
    var items: [SearchItem] = []
    var isLoading = true
    var errorText: String?

    init(providerID: Int, regionCode: String, repository: LibraryRepository) {
        self.providerID = providerID
        self.regionCode = regionCode
        self.repository = repository
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
        .task(id: model.filterID) { await model.load() }
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
