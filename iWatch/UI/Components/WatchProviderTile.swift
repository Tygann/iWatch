import SwiftUI

struct WatchProviderTile: View {
    let provider: MediaSupplementaryDetails.WatchProvider
    let availabilityLabel: String

    var body: some View {
        ServiceProviderTile(
            name: provider.name,
            logoPath: provider.logoPath,
            size: 54,
            caption: availabilityLabel,
            captionLineLimit: 1
        )
    }
}
