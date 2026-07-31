// Core/Domain/SearchItem.swift
import Foundation

struct SearchItem: Identifiable, Hashable, Sendable {
    let id: Int
    let kind: MediaKind    // .movie / .show (we ignore .person here)
    let traktID: Int?
    let title: String
    let posterPath: String?
    let year: String?

    init(id: Int,
         kind: MediaKind,
         traktID: Int? = nil,
         title: String,
         posterPath: String?,
         year: String?) {
        self.id = id
        self.kind = kind
        self.traktID = traktID
        self.title = title
        self.posterPath = posterPath
        self.year = year
    }

    var mediaID: MediaID {
        MediaID(kind: kind, id: id, traktID: traktID)
    }
}
