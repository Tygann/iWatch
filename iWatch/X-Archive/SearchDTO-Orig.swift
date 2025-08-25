//import Foundation
//
//struct SearchPageDTO: Decodable {
//    let results: [SearchResultDTO]
//}
//
//struct SearchResultDTOOrig: Decodable, Sendable {
//    let id: Int
//    let media_type: String          // "movie" or "tv" (others ignored)
//    let title: String?              // movies
//    let name: String?               // tv
//    let poster_path: String?
//    let overview: String?
//    let release_date: String?
//    let first_air_date: String?
//
//    var simple: SimpleDTO? {
//        switch media_type {
//        case "movie":
//            let year = release_date.flatMap { String($0.prefix(4)) }.flatMap(Int.init)
//            return SimpleDTO(id: id,
//                             title: title ?? "Movie",
//                             posterPath: poster_path,
//                             overview: overview,
//                             year: year,
//                             kind: .movie)
//        case "tv":
//            let year = first_air_date.flatMap { String($0.prefix(4)) }.flatMap(Int.init)
//            return SimpleDTO(id: id,
//                             title: name ?? "TV Show",
//                             posterPath: poster_path,
//                             overview: overview,
//                             year: year,
//                             kind: .tv)
//        default:
//            return nil
//        }
//    }
//}
