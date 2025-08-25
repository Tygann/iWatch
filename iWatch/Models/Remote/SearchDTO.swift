// Models/Remote/SearchResultDTO.swift
import Foundation

public enum SearchMediaType: String, Decodable { case movie, tv }

public struct SearchResultDTO: Decodable, Identifiable {
    public let id: Int
    public let mediaType: SearchMediaType?
    public let title: String
    public let posterPath: String?
    public let backdropPath: String?
    public let year: Int?

    // ✅ NEW: for Suggested ranking / tie-breaking
    public let genreIDs: [Int]?
    public let popularity: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case mediaType    = "media_type"
        case title, name
        case posterPath   = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate  = "release_date"
        case firstAirDate = "first_air_date"
        // ✅ NEW
        case genreIDs     = "genre_ids"
        case popularity
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id           = try c.decode(Int.self, forKey: .id)
        posterPath   = try c.decodeIfPresent(String.self, forKey: .posterPath)
        backdropPath = try c.decodeIfPresent(String.self, forKey: .backdropPath)
        genreIDs     = try c.decodeIfPresent([Int].self, forKey: .genreIDs)   // ✅
        popularity   = try c.decodeIfPresent(Double.self, forKey: .popularity) // ✅

        let decodedType = try? c.decode(SearchMediaType.self, forKey: .mediaType)
        let movieTitle  = try? c.decode(String.self, forKey: .title)
        let showName    = try? c.decode(String.self, forKey: .name)
        let relDate     = try? c.decodeIfPresent(String.self, forKey: .releaseDate)
        let firstAir    = try? c.decodeIfPresent(String.self, forKey: .firstAirDate)

        let inferredType: SearchMediaType = {
            if let t = decodedType { return t }
            if movieTitle != nil || relDate  != nil { return .movie }
            if showName   != nil || firstAir != nil { return .tv }
            return .movie
        }()

        switch inferredType {
        case .movie:
            title = movieTitle ?? showName ?? ""
            year  = (relDate ?? firstAir).flatMap { Int($0.prefix(4)) }
        case .tv:
            title = showName ?? movieTitle ?? ""
            year  = (firstAir ?? relDate).flatMap { Int($0.prefix(4)) }
        }

        mediaType = decodedType ?? inferredType
    }
}

//public struct SearchResultDTO: Decodable, Identifiable {
//    public let id: Int
//    public let mediaType: SearchMediaType
//    public let title: String
//    public let posterPath: String?
//    public let year: Int?
//
//    enum CodingKeys: String, CodingKey {
//        case id, mediaType, title, name, posterPath, releaseDate, firstAirDate
//    }
//
//    public init(from decoder: Decoder) throws {
//        let c = try decoder.container(keyedBy: CodingKeys.self)
//        id = try c.decode(Int.self, forKey: .id)
//        mediaType = try c.decode(SearchMediaType.self, forKey: .mediaType)
//        posterPath = try? c.decodeIfPresent(String.self, forKey: .posterPath)
//
//        switch mediaType {
//        case .movie:
//            let t = (try? c.decode(String.self, forKey: .title)) ?? ""
//            title = t
//            if let d = try? c.decodeIfPresent(String.self, forKey: .releaseDate), let y = d.prefix(4).toInt {
//                year = y
//            } else { year = nil }
//        case .tv:
//            let n = (try? c.decode(String.self, forKey: .name)) ?? ""
//            title = n
//            if let d = try? c.decodeIfPresent(String.self, forKey: .firstAirDate), let y = d.prefix(4).toInt {
//                year = y
//            } else { year = nil }
//        }
//    }
//}

fileprivate extension Substring {
    var toInt: Int? { Int(String(self)) }
}
