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
                                ProviderResultsView(provider: provider, initialKind: .movie, regionCode: model.regionCode)
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

    var kind: MediaKind
    var offerType: ProviderOfferType = .stream
    var items: [SearchItem] = []
    var isLoading = true
    var errorText: String?

    init(kind: MediaKind, providerID: Int, regionCode: String, repository: LibraryRepository) {
        self.kind = kind
        self.providerID = providerID
        self.regionCode = regionCode
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await repository.discover(
                kind: kind,
                providerID: providerID,
                offerType: offerType,
                regionCode: regionCode
            )
            errorText = nil
        } catch {
            guard !error.isCancelled else { return }
            items = []
            errorText = error.localizedDescription
        }
    }
}

struct ProviderResultsView: View {
    let provider: DiscoveryProvider
    let initialKind: MediaKind
    let regionCode: String

    @Environment(AppContainer.self) private var container
    @State private var model: ProviderResultsModel?

    var body: some View {
        Group {
            if let model {
                ProviderResultsBody(model: model, regionCode: regionCode)
            } else {
                ProgressView().task {
                    let newModel = ProviderResultsModel(kind: initialKind, providerID: provider.id, regionCode: regionCode, repository: container.libraryRepository)
                    await newModel.load()
                    guard !Task.isCancelled else { return }
                    model = newModel
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
        VStack(spacing: 12) {
            DiscoveryScopePicker("Media Type", selection: $model.kind) {
                Text("Movies").tag(MediaKind.movie)
                Text("Shows").tag(MediaKind.show)
            }
            .onChange(of: model.kind) { _, _ in Task { await model.load() } }

            HStack {
                Menu {
                    Picker("Availability", selection: $model.offerType) {
                        ForEach(ProviderOfferType.allCases) { offerType in
                            Text(offerType.title).tag(offerType)
                        }
                    }
                } label: {
                    Label(model.offerType.title, systemImage: "line.3.horizontal.decrease")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)

                Spacer()
            }
            .padding(.horizontal)
            .onChange(of: model.offerType) { _, _ in Task { await model.load() } }

            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText = model.errorText {
                ContentUnavailableView("Titles Unavailable", systemImage: "wifi.exclamationmark", description: Text(errorText))
            } else if model.items.isEmpty {
                ContentUnavailableView("No Titles", systemImage: "play.tv", description: Text("No \(model.offerType.title.lowercased()) titles were found for this service in \(regionCode)."))
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.items) { item in
                            MediaTile(ref: item.mediaID, title: item.title, posterPath: item.posterPath, showTitle: true)
                                .frame(width: 110)
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
    }
}
