import SwiftUI

/// App Store–style rating badge: number + stars with smooth fractional fill.
struct RatingBadge: View {
    let rating: Double          // 0…maxRating
    var maxRating: Int = 5
    var starSize: CGFloat = 13
    var starSpacing: CGFloat = 2
    var showNumber: Bool = true

    private var clamped: Double { min(max(rating, 0), Double(maxRating)) }

    var body: some View {
//        VStack(spacing: 4) {
//            if showNumber {
//                Text(clamped, format: .number.precision(.fractionLength(1)))
//                    .font(.title3.bold())
//                    .fontDesign(.rounded)
//                    .monospacedDigit()
//            }

            StarsRow(
                rating: clamped,
                maxRating: maxRating,
                spacing: starSpacing
            )
//            .font(.system(size: starSize, weight: .regular))
//            .symbolRenderingMode(.monochrome)
//            .foregroundStyle(.secondary)    // matches App Store tone
//        }
        .accessibilityLabel("Rating \(clamped, specifier: "%.1f") out of \(maxRating) stars")
    }
}

/// Draws 5 outline stars with a per-star masked fill for smooth fractions.
private struct StarsRow: View {
    let rating: Double     // already clamped
    let maxRating: Int
    let spacing: CGFloat

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<maxRating, id: \.self) { i in
                let fill = max(min(rating - Double(i), 1), 0)   // 0…1 for this star

                ZStack(alignment: .leading) {
                    // Outline star (baseline for alignment)
                    Image(systemName: "star")

                    // Filled star, masked to the fractional width of this star
                    Image(systemName: "star.fill")
                        .mask(alignment: .leading) {
                            GeometryReader { geo in
                                Rectangle()
                                    .frame(width: geo.size.width * fill, alignment: .leading)
                            }
                        }
                }
            }
        }
    }
}









//import SwiftUI
//
//struct RatingBadge: View {
//    struct ClipShape: Shape {
//        let width: Double
//
//        func path(in rect: CGRect) -> Path {
//            Path(CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height))
//        }
//    }
//
//    let rating: Double
//    let maxRating: Int
//
////    init(rating: Double, maxRating: Int) {
////        self.maxRating = maxRating
////        self.rating = rating
////    }
//
//    var body: some View {
//        HStack(spacing: 0) {
//            ForEach(0..<maxRating, id: \.self) { _ in
//                Text(Image(systemName: "star"))
////                    .foregroundColor(.blue)
//                    .aspectRatio(contentMode: .fill)
//            }
//        }.overlay(
//            GeometryReader { reader in
//                HStack(spacing: 0) {
//                    ForEach(0..<maxRating, id: \.self) { _ in
//                        Image(systemName: "star.fill")
////                            .foregroundColor(.blue)
//                            .aspectRatio(contentMode: .fit)
//                    }
//                }
//                .clipShape(
//                    ClipShape(width: (reader.size.width / CGFloat(maxRating)) * CGFloat(rating))
//                )
//            }
//        )
//    }
//}
