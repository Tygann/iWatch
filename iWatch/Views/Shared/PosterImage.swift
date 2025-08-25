import SwiftUI

struct PosterImage: View {
    let path: String?
    var width: CGFloat = 110
    var height: CGFloat = 165
    var cornerRadius: CGFloat = 12

    private var url: URL? { TMDBImage.url(path: path, kind: .poster(width: 342)) }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .clipped()
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.gray.opacity(0.12))
            Image(systemName: "film")
                .font(.title3)
                .foregroundStyle(.gray.opacity(0.5))
        }
    }
}



//import SwiftUI
//import SDWebImageSwiftUI
//
//private func tmdbPosterURL(for path: String?, width: Int = 342) -> URL? {
//    guard var p = path, !p.isEmpty else { return nil }
//    if !p.hasPrefix("/") { p = "/" + p }                 // normalize
//    return URL(string: "https://image.tmdb.org/t/p/w\(width)\(p)")
//}
//
//struct PosterImage: View {
//    let path: String?
//    var width: CGFloat = 110
//    var height: CGFloat = 165
//    var cornerRadius: CGFloat = 12
//
//    var body: some View {
//        Group {
//            if let url = tmdbPosterURL(for: path) {
//                WebImage(url: url)
//                    .resizable()
//                    .scaledToFill()
//                    .transition(.fade(duration: 0.25))
//            } else {
//                Rectangle().opacity(0.12)
//            }
//        }
//        .frame(width: width, height: height)
//        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
//        .clipped()
//    }
//}






//import SwiftUI
//import SDWebImageSwiftUI
//
//enum TMDBImage {
//    static func posterURL(path: String?, size: String = "w342") -> URL? {
//        guard let path, !path.isEmpty else { return nil }
//        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
//    }
//}
//
//struct PosterImage: View {
//    private let url: URL?
//
//    init(path: String?, size: String = "w342") {
//        self.url = TMDBImage.posterURL(path: path, size: size)
//    }
//
//    init(url: URL?) { self.url = url }
//
//    var body: some View {
//        WebImage(url: url) { image in
//            image
//                .resizable()
//                .scaledToFit()                 // you control size via .frame outside
//        } placeholder: {
//            RoundedRectangle(cornerRadius: 12)
//                .fill(.quaternary)
//        }
//        .indicator(.activity)                  // SDWebImage modifiers work here
//        .transition(.fade(duration: 0.25))
//        .allowsHitTesting(false)
//    }
//}
