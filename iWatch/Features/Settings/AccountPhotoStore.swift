import Foundation

struct AccountPhotoStore {
    var directory = URL.applicationSupportDirectory.appending(path: "AccountPhotos", directoryHint: .isDirectory)

    func photo(for id: UUID) -> Data? {
        try? Data(contentsOf: file(for: id))
    }

    func setPhoto(_ photo: Data?, for id: UUID) throws {
        let url = file(for: id)
        if let photo {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try photo.write(to: url, options: [.atomic, .completeFileProtection])
        } else {
            do {
                try FileManager.default.removeItem(at: url)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                // Removing a photo that is already absent succeeds.
            }
        }
    }

    private func file(for id: UUID) -> URL {
        directory.appending(path: id.uuidString).appendingPathExtension("png")
    }
}
