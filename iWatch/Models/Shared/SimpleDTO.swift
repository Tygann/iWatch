import Foundation

public struct SimpleDTO: Sendable, Hashable {
    public let id: Int
    public let kind: MediaRef.Kind           // ← keep this (don’t use MediaItem.Kind)
    public let title: String
    public let posterPath: String?
    public let year: Int?
    public let genreIDs: [Int]?              // for Suggested ranking

    public init(
        id: Int,
        kind: MediaRef.Kind,
        title: String,
        posterPath: String?,
        year: Int?,
        genreIDs: [Int]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.posterPath = posterPath
        self.year = year
        self.genreIDs = genreIDs
    }
}




//public struct SimpleDTO: Hashable, Identifiable {
//    public let id: Int
//    public let kind: MediaRef.Kind
//    public let title: String
//    public let posterPath: String?
//    public let year: Int?
//}





//import Foundation
//
//struct SimpleDTO: Identifiable, Hashable, Sendable {
//    let id: Int
//    let title: String
//    let posterPath: String?
//    let overview: String?
//    let year: Int?
//    let kind: MediaItem.Kind   // .movie or .tv
//
//    var posterURL: URL? {
//        guard let path = posterPath else { return nil }
//        return URL(string: "https://image.tmdb.org/t/p/w342\(path)")
//    }
//}
