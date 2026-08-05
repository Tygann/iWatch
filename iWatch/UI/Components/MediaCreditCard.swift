import SwiftUI

struct MediaCreditCard: View {
    let name: String
    let subtitle: String?
    let profilePath: String?

    var body: some View {
        VStack(spacing: 8) {
            ProfileImage(
                path: profilePath,
                width: 82,
                height: 82,
                cornerRadius: 41,
                cropAlignment: .center,
                cropOffsetY: 6
            )
            .clipShape(Circle())
            .glassEffect(.regular, in: .circle)
            .shadow(radius: 4)

            Text(name)
                .font(.caption.weight(.semibold))
                .lineLimit(2)

            Text(subtitle ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(width: 92)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}
