//import Foundation
//
//struct MoviePageDTO: Decodable {
//    let results: [MovieDTO]
//}
//
//struct MovieDTOOrig: Decodable, Sendable {
//    let id: Int
//    let title: String
//    let poster_path: String?
//    let overview: String?
//    let release_date: String?
//
//    var simple: SimpleDTO {
//        let year: Int? = release_date.flatMap { String($0.prefix(4)) }.flatMap(Int.init)
//        return SimpleDTO(id: id,
//                         title: title,
//                         posterPath: poster_path,
//                         overview: overview,
//                         year: year,
//                         kind: .movie)
//    }
//}
