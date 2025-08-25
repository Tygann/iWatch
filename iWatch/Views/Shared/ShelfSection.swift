import SwiftUI

struct ShelfSection: View {
    let title: String
    let items: [SimpleDTO]
    @Binding var selectedRef: MediaRef?

    init(title: String, items: [SimpleDTO], selectedRef: Binding<MediaRef?>) {
        self.title = title
        self.items = items
        self._selectedRef = selectedRef
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items, id: \.id) { item in
                        MediaTile(
                            ref: .init(id: item.id, kind: item.kind),
                            title: item.title,
                            posterPath: item.posterPath,
                            showTitle: true,
                            selectedRef: $selectedRef
                        )
                        .frame(width: 120)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}
