import Observation
import SwiftUI

@MainActor
@Observable
private final class PersonDetailScreenModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(PersonDetails)
        case failed(String)
    }

    let personID: Int
    private let repository: PeopleRepository

    var loadState: LoadState = .idle

    init(personID: Int, repository: PeopleRepository) {
        self.personID = personID
        self.repository = repository
    }

    func load() async {
        loadState = .loading

        do {
            loadState = .loaded(try await repository.personDetails(id: personID))
        } catch is CancellationError {
            return
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}

struct PersonDetailView: View {
    let personID: Int
    let name: String

    @Environment(AppContainer.self) private var container
    @State private var model: PersonDetailScreenModel?

    var body: some View {
        Group {
            if let model {
                PersonDetailBody(model: model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard model == nil else { return }

            let newModel = PersonDetailScreenModel(
                personID: personID,
                repository: container.peopleRepository
            )
            model = newModel
            await newModel.load()
        }
    }
}

private struct PersonDetailBody: View {
    @Bindable var model: PersonDetailScreenModel

    var body: some View {
        switch model.loadState {
        case .idle, .loading:
            ProgressView("Loading person…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .loaded(person):
            personContent(person)

        case let .failed(message):
            ContentUnavailableView {
                Label("Unable to Load Person", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await model.load() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func personContent(_ person: PersonDetails) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 16) {
                    ProfileImage(
                        path: person.profilePath,
                        width: 180,
                        height: 240,
                        cornerRadius: 22
                    )
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                    .shadow(radius: 6)

                    Text(person.name)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                if let biography = person.biography?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !biography.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Biography")
                            .font(.title3.bold())

                        Text(biography)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !person.knownFor.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Known For")
                            .font(.title3.bold())

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 12) {
                                ForEach(person.knownFor) { item in
                                    MediaTile(
                                        ref: item.mediaID,
                                        title: item.title,
                                        posterPath: item.posterPath,
                                        showTitle: true
                                    )
                                }
                            }
                        }
                        .contentMargins(.horizontal, 20, for: .scrollContent)
                        .padding(.horizontal, -20)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .refreshable {
            await model.load()
        }
    }
}

#Preview {
    let container = AppContainer.preview()
    return NavigationStack {
        PersonDetailView(personID: 31, name: "Tom Hanks")
    }
    .environment(container)
    .environment(container.session)
}
