import SwiftUI

struct MediaCollectionRow<Destination: View, Content: View>: View {
    let title: String
    let destination: () -> Destination
    let content: () -> Content

    init(
        title: String,
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.destination = destination
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                destination()
            } label: {
                Text(title)
                    .font(.title3.weight(.bold))
                Image(systemName: "chevron.right")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading)
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    content()
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
        .padding(.top, 12)
    }
}
