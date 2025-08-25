import Foundation

enum TMDBImage {
    enum Kind {
        case poster(width: Int)     // 154, 185, 342, 500, 780
        case backdrop(width: Int)   // 300, 780, 1280
        case profile(width: Int)    // 45, 185, 300
        case original
    }

    static func url(path: String?, kind: Kind) -> URL? {
        guard var p = path, !p.isEmpty else { return nil }
        if !p.hasPrefix("/") { p = "/" + p } // normalize
        let base = "https://image.tmdb.org/t/p/"
        let size: String = switch kind {
            case .poster(let w):   "w\(w)"
            case .backdrop(let w): "w\(w)"
            case .profile(let w):  "w\(w)"
            case .original:        "original"
        }
        return URL(string: base + size + p)
    }
}



//import Foundation
//
//enum TMDBImage {
//    enum Kind {
//        case poster(width: Int)     // typical: 342, 500
//        case backdrop(width: Int)   // typical: 780
//        case profile(width: Int)    // headshots: 185, 300
//        case original               // full size
//    }
//
//    static func url(path: String?, kind: Kind) -> URL? {
//        guard var p = path, !p.isEmpty else { return nil }
//        if !p.hasPrefix("/") { p = "/" + p }   // normalize
//
//        let base = "https://image.tmdb.org/t/p/"
//        let size: String
//        switch kind {
//        case .poster(let w):   size = "w\(w)"
//        case .backdrop(let w): size = "w\(w)"
//        case .profile(let w):  size = "w\(w)"
//        case .original:        size = "original"
//        }
//        return URL(string: base + size + p)
//    }
//}
