import Foundation

struct TVPageDTO: Decodable {
    let results: [TVDTO]
}

struct TVDTO: Decodable, Sendable {
    let id: Int
    let name: String
    let poster_path: String?
    let overview: String?
    let first_air_date: String?

    var simple: SimpleDTO {
        let year: Int? = first_air_date.flatMap { String($0.prefix(4)) }.flatMap(Int.init)
        return SimpleDTO(id: id,
                         title: name,
                         posterPath: poster_path,
                         overview: overview,
                         year: year,
//                         kind: .show)
                         kind: .tv)
    }
}
