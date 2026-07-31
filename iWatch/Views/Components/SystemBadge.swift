import Foundation
import SwiftUI

struct SystemBadge: View {
    let label: String
    let color: Color
    let height: CGFloat

    var body: some View {
        Text(label)
            .font(.caption2.bold())
//            .foregroundColor(.white)
            .frame(height: height)
            .frame(minWidth: height)
            .padding(.horizontal, label.count > 1 ? 4 : 0)
            .glassEffect(.regular.tint(.red.opacity(0.8)))
//            .background(
//                Capsule()
//                    .fill(color)
//            )
    }
}
