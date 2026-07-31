import Foundation

enum DateFormatters {
    static let tmdbYMD: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    static let year: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        f.locale = .init(identifier: "en_US_POSIX")
        return f
    }()

    static func yearString(from iso: String?) -> String? {
        guard let iso, let y = iso.split(separator: "-").first else { return nil }
        return String(y)
    }
}
