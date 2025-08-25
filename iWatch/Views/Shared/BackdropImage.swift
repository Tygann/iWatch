import SwiftUI

struct BackdropImage: View {
    let path: String?
    var height: CGFloat = 220

    private var url: URL? { TMDBImage.url(path: path, kind: .backdrop(width: 780)) }

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
//        .frame(height: height)
        .clipped()
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Rectangle().fill(.gray.opacity(0.12))
    }
}







//import SwiftUI
//import SDWebImageSwiftUI
//
//private func tmdbBackdropURL(for path: String?, width: Int = 780) -> URL? {
//    guard var p = path, !p.isEmpty else { return nil }
//    if !p.hasPrefix("/") { p = "/" + p }
//    return URL(string: "https://image.tmdb.org/t/p/w\(width)\(p)")
//}
//
//struct BackdropImage: View {
//    let path: String?
//    var height: CGFloat = 220
//
//    var body: some View {
//        Group {
//            if let url = tmdbBackdropURL(for: path) {
//                WebImage(url: url)
//                    .resizable()
//                    .scaledToFill()
//                    .transition(.fade(duration: 0.25))
//            } else {
//                Rectangle().opacity(0.12)
//            }
//        }
//        .frame(height: height)
//        .clipped()
//    }
//}









//import SwiftUI
//import SDWebImageSwiftUI
//
//struct BackdropImage: View {
//    let path: String?
//
//    var body: some View {
//        Group {
//            if let path {
//                WebImage(url: URL(string: "https://image.tmdb.org/t/p/w780\(path)"))
//                    .resizable()
//                    .scaledToFill()
//                    .transition(.fade(duration: 0.25))
//            } else {
//                Rectangle().opacity(0.12)
//            }
//        }
//    }
//}
