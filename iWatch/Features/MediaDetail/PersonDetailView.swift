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

    var person: PersonDetails? {
        guard case let .loaded(person) = loadState else { return nil }
        return person
    }

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
        .toolbar {
            if let person = model?.person {
                ToolbarItem(placement: .topBarTrailing) {
                    PersonLinksMenu(person: person)
                }
            }
        }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var biographyExpanded = false
    @State private var biographyFullLines = 0

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

                    metadata(for: person)
                }

                if let biography = person.biography?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !biography.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Biography")
                            .font(.title3.bold())

                        Text(biography)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(biographyExpanded || dynamicTypeSize.isAccessibilitySize ? nil : 6)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(biography)
                            .overlay {
                                Text(biography)
                                    .font(.callout)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .onNumberOfLinesChange { biographyFullLines = $0 }
                                    .opacity(0)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }

                        if !dynamicTypeSize.isAccessibilitySize, biographyFullLines > 6 {
                            Button(biographyExpanded ? "Less" : "More") {
                                withAnimation(.snappy) {
                                    biographyExpanded.toggle()
                                }
                            }
                            .font(.caption.bold())
                        }
                    }
                }

                if !person.knownFor.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        NavigationLink {
                            PersonFilmographyView(person: person)
                        } label: {
                            HStack(spacing: 6) {
                                Text("Known For")
                                    .font(.title3.bold())
                                Image(systemName: "chevron.right")
                                    .font(.callout.bold())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 12) {
                                ForEach(person.knownFor) { item in
                                    PersonCreditPosterTile(credit: item)
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

    @ViewBuilder
    private func metadata(for person: PersonDetails) -> some View {
        let department = person.knownForDepartment?.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = person.placeOfBirth?.trimmingCharacters(in: .whitespacesAndNewlines)

        if department?.isEmpty == false || person.birthday != nil || place?.isEmpty == false {
            VStack(spacing: 4) {
                if let department, !department.isEmpty {
                    Text(department)
                }

                if let birthday = person.birthday {
                    if let deathday = person.deathday {
                        Text("\(birthday.formatted(date: .abbreviated, time: .omitted)) – \(deathday.formatted(date: .abbreviated, time: .omitted))")
                    } else {
                        Text("Born \(birthday.formatted(date: .abbreviated, time: .omitted))")
                    }
                }

                if let place, !place.isEmpty {
                    Text(place)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct PersonCreditPosterTile: View {
    let credit: PersonDetails.Credit
    var width: CGFloat = 110

    var body: some View {
        NavigationLink {
            MediaDetailView(ref: credit.media.mediaID)
        } label: {
            VStack(spacing: 6) {
                PosterImage(path: credit.media.posterPath, width: width)

                Text(credit.media.title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2, reservesSpace: true)

                Text(credit.role ?? credit.departments.first ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(width: width, alignment: .top)
            .multilineTextAlignment(.center)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(creditAccessibilityLabel)
    }

    private var creditAccessibilityLabel: String {
        [credit.media.title, credit.media.year, credit.role ?? credit.departments.first]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

private struct PersonFilmographyView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case movies = "Movies"
        case television = "TV"

        var id: Self { self }
    }

    let person: PersonDetails
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var filter: Filter = .all

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    private var filteredCredits: [PersonDetails.Credit] {
        person.credits.filter { credit in
            switch filter {
            case .all: true
            case .movies: credit.media.kind == .movie
            case .television: credit.media.kind == .show
            }
        }
    }

    private var groupedCredits: [(year: String, credits: [PersonDetails.Credit])] {
        let groups = Dictionary(grouping: filteredCredits) { $0.media.year ?? "Date Unknown" }
        return groups.map { (year: $0.key, credits: $0.value) }.sorted {
            if $0.year == "Date Unknown" { return false }
            if $1.year == "Date Unknown" { return true }
            return $0.year > $1.year
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Picker("Credit Type", selection: $filter) {
                    ForEach(Filter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                ForEach(groupedCredits, id: \.year) { group in
                    Section {
                        if dynamicTypeSize.isAccessibilitySize {
                            LazyVStack(spacing: 12) {
                                ForEach(group.credits) { credit in
                                    NavigationLink {
                                        MediaDetailView(ref: credit.media.mediaID)
                                    } label: {
                                        PersonFilmographyRow(credit: credit)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                                ForEach(group.credits) { credit in
                                    DiscoveryPosterTile(
                                        item: credit.media,
                                        showTitle: true,
                                        showKindBadge: filter == .all,
                                        subtitle: credit.role ?? credit.departments.first,
                                        showYearBadge: false
                                    )
                                }
                            }
                        }
                    } header: {
                        Text(group.year)
                            .font(.headline.bold())
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
        .navigationTitle("Filmography")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if filteredCredits.isEmpty {
                ContentUnavailableView(
                    "No Credits",
                    systemImage: "film.stack",
                    description: Text("No \(filter.rawValue.lowercased()) credits are available for \(person.name).")
                )
            }
        }
    }
}

private struct PersonFilmographyRow: View {
    let credit: PersonDetails.Credit

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(path: credit.media.posterPath, width: 48, cornerRadius: 7)

            VStack(alignment: .leading, spacing: 4) {
                Text(credit.media.title)
                    .font(.body.weight(.semibold))

                if let role = credit.role ?? credit.departments.first {
                    Text(role)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
    }
}

private struct PersonLinksMenu: View {
    let person: PersonDetails

    private var tmdbURL: URL {
        URL(string: "https://www.themoviedb.org/person/\(person.id)")!
    }

    var body: some View {
        Menu {
            ShareLink(item: tmdbURL, subject: Text(person.name)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Link(destination: tmdbURL) {
                Label("View on TMDb", systemImage: "film")
            }

            if let homepage = person.homepage {
                Link(destination: homepage) {
                    Label("Official Website", systemImage: "globe")
                }
            }

            if !externalLinks.isEmpty {
                Divider()
                ForEach(externalLinks, id: \.label) { link in
                    Link(destination: link.url) {
                        Label(link.label, systemImage: link.systemImage)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("More")
    }

    private var externalLinks: [(label: String, systemImage: String, url: URL)] {
        var links: [(String, String, URL)] = []
        appendLink(label: "IMDb", systemImage: "star", base: "https://www.imdb.com/name/", id: person.externalIDs.imdb, to: &links)
        appendLink(label: "Instagram", systemImage: "camera", base: "https://www.instagram.com/", id: person.externalIDs.instagram, to: &links)
        appendLink(label: "TikTok", systemImage: "play.rectangle", base: "https://www.tiktok.com/@", id: person.externalIDs.tiktok, to: &links)
        appendLink(label: "X", systemImage: "at", base: "https://x.com/", id: person.externalIDs.twitter, to: &links)
        appendLink(label: "Facebook", systemImage: "person.2", base: "https://www.facebook.com/", id: person.externalIDs.facebook, to: &links)
        appendLink(label: "YouTube", systemImage: "play.rectangle.fill", base: "https://www.youtube.com/channel/", id: person.externalIDs.youtube, to: &links)
        return links
    }

    private func appendLink(
        label: String,
        systemImage: String,
        base: String,
        id: String?,
        to links: inout [(String, String, URL)]
    ) {
        guard let id = id?.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")),
              !id.isEmpty,
              let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: base + encodedID) else { return }
        links.append((label, systemImage, url))
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
