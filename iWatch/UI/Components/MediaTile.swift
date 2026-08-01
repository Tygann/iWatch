import SwiftUI

struct MediaTile<ExtraMenu: View>: View {
    let ref: MediaRef
    let title: String
    let posterPath: String?
    var showTitle: Bool = false
    @Binding var selectedRef: MediaRef?
    var onSelect: (() -> Void)?

    // extra context‑menu items (optional)
    @ViewBuilder var extraMenu: () -> ExtraMenu

    init(
        ref: MediaRef,
        title: String,
        posterPath: String?,
        showTitle: Bool = false,
        selectedRef: Binding<MediaRef?>,
        onSelect: (() -> Void)? = nil,
        @ViewBuilder extraMenu: @escaping () -> ExtraMenu = { EmptyView() }
    ) {
        self.ref = ref
        self.title = title
        self.posterPath = posterPath
        self.showTitle = showTitle
        self._selectedRef = selectedRef
        self.onSelect = onSelect
        self.extraMenu = extraMenu
    }

    var body: some View {
        Button {
            if let onSelect {
                onSelect()
            } else {
                selectedRef = ref
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                PosterImage(path: posterPath)
                if showTitle {
                    Text(title)
                        .font(.caption)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .contextMenu {
            extraMenu()
            WatchlistMenu(ref: ref, title: title, posterPath: posterPath)
        }
    }
}
