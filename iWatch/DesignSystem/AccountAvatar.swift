import SwiftUI

struct AccountAvatar: View {
    var localPhoto: Data? = nil
    var photoURL: URL? = nil
    let size: CGFloat

    var body: some View {
        Group {
            if let localPhoto, let image = UIImage(data: localPhoto) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let photoURL {
                AsyncImage(url: photoURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.secondary)
    }
}
