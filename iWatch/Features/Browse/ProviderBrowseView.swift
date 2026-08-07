import Observation
import SwiftUI

@MainActor
@Observable
private final class ProviderBrowseModel {
    private let repository: LibraryRepository
    let regionCode: String

    var kind: MediaKind
    var providers: [DiscoveryProvider] = []
    var isLoading = true
    var errorText: String?

    init(kind: MediaKind, repository: LibraryRepository, regionCode: String) {
        self.kind = kind
        self.repository = repository
        self.regionCode = regionCode
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            providers = try await repository.watchProviders(kind: kind, regionCode: regionCode)
            errorText = nil
        } catch {
            guard !error.isCancelled else { return }
            providers = []
            errorText = error.localizedDescription
        }
    }
}

struct ProviderBrowseView: View {
    let initialKind: MediaKind

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
                            kind: initialKind,
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
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct ProviderBrowseBody: View {
    @Bindable var model: ProviderBrowseModel

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 16)]

    var body: some View {
        VStack(spacing: 12) {
            Picker("Media Type", selection: $model.kind) {
                Text("Movies").tag(MediaKind.movie)
                Text("Shows").tag(MediaKind.show)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: model.kind) { _, _ in Task { await model.load() } }

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
                                    ProviderResultsView(provider: provider, initialKind: model.kind, regionCode: model.regionCode)
                                } label: {
                                    ProviderLogo(provider: provider)
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
}

private struct ProviderLogo: View {
    let provider: DiscoveryProvider

    var body: some View {
        VStack(spacing: 8) {
            CachedArtworkImage(
                url: ImageURLBuilder.make(provider.logoPath, size: .profile),
                targetSize: CGSize(width: 72, height: 72)
            ) { $0.resizable().scaledToFill() } placeholder: {
                RoundedRectangle(cornerRadius: 16).fill(.quaternary).overlay { Image(systemName: "play.tv") }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(provider.name)
                .font(.caption)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(provider.name)
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

private struct ProviderResultsView: View {
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
            Picker("Media Type", selection: $model.kind) {
                Text("Movies").tag(MediaKind.movie)
                Text("Shows").tag(MediaKind.show)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: model.kind) { _, _ in Task { await model.load() } }

            Picker("Availability", selection: $model.offerType) {
                ForEach(ProviderOfferType.allCases) { offerType in
                    Text(offerType.title).tag(offerType)
                }
            }
            .pickerStyle(.segmented)
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
