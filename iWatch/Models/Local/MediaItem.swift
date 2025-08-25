// MediaItem.swift
import Foundation
import SwiftData

// MARK: - MediaItem: Persisted library entity in SwiftData with additional fields (overview, posterURL, timestamps, etc.).
@Model
final class MediaItem {
    enum Kind: String, Codable, CaseIterable, Identifiable { case movie, tv; var id: String { rawValue } }

    @Attribute(.unique) var id: String          // "movie:123" or "tv:456"
    var remoteID: Int
    var kindRaw: String                          // <-- add this
    var kind: Kind {                              // convenience accessor for UI
        get { Kind(rawValue: kindRaw) ?? .movie }
        set { kindRaw = newValue.rawValue }
    }

    var title: String
    var posterPath: String?
    var posterURL: URL? {
        guard let path = posterPath, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w342\(path)")
    }
    var overview: String?
    var year: Int?
    var dateAdded: Date = Date()

    init(remoteID: Int, kind: Kind, title: String, posterPath: String?, overview: String?, year: Int?) {
        self.id = "\(kind.rawValue):\(remoteID)"
        self.remoteID = remoteID
        self.kindRaw = kind.rawValue            // <-- set raw kind
        self.title = title
        self.posterPath = posterPath
        self.overview = overview
        self.year = year
    }
}


//import Foundation
//import SwiftData
//
//@Model
//final class MediaItem {
//    enum Kind: String, Codable, CaseIterable, Identifiable {
//        case movie, tv
//        var id: String { rawValue }
//    }
//
//    @Attribute(.unique) var id: String              // "movie:123" or "tv:456"
//    var remoteID: Int
//    var kind: Kind
//    var title: String
//    var posterPath: String?
//    var overview: String?
//    var year: Int?
////    var dateAdded: Date = .now
//    var dateAdded: Date = Date()
//
//    init(remoteID: Int, kind: Kind, title: String, posterPath: String?, overview: String?, year: Int?) {
//        self.id = "\(kind.rawValue):\(remoteID)"
//        self.remoteID = remoteID
//        self.kind = kind
//        self.title = title
//        self.posterPath = posterPath
//        self.overview = overview
//        self.year = year
//    }
//}
