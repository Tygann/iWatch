import Foundation

struct ImageURLBuilder {
    enum Size: String {
        case posterSmall = "w185"
        case posterTile = "w342"
        case posterLarge = "w500"
        case backdrop = "w780"
        case original = "original"
    }

    static let base = URL(string: "https://image.tmdb.org/t/p/")!

    static func make(_ path: String?, size: Size) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return base.appendingPathComponent(size.rawValue).appendingPathComponent(path)
    }
}
