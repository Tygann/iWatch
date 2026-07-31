import Foundation

final class PeopleRepository {
    private let tmdb: TMDbService

    init(tmdb: TMDbService) {
        self.tmdb = tmdb
    }

    func personDetails(id: Int) async throws -> PersonDetails {
        TMDbMappers.person(try await tmdb.personDetails(id: id))
    }
}
