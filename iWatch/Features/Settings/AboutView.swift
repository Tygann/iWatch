import SwiftUI
import StoreKit

// MARK: - About Screen

struct AboutView: View {
    @Environment(\.requestReview) private var requestReview
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        List {
            appIdentity

            Section {
                NavigationLink { SyncSupportView() } label: {
                    SettingsNavigationLabel(title: "Contact Support", systemImage: "questionmark.circle")
                }
                ShareLink(item: AppDistributionPresentation.shareText) {
                    SettingsNavigationLabel(title: "Share iWatch", systemImage: "square.and.arrow.up")
                }
                Button { requestReview() } label: {
                    SettingsNavigationLabel(title: "Rate iWatch", systemImage: "star")
                }
            }

            Section {
                Link(destination: URL(string: "https://tylerkeegan.com/iwatch/privacy/")!) {
                    SettingsNavigationLabel(title: "Privacy Policy", systemImage: "hand.raised")
                }
                NavigationLink {
                    AcknowledgmentsView()
                } label: {
                    SettingsNavigationLabel(title: "Acknowledgments", systemImage: "info.circle")
                }
            }
        }
        .navigationTitle("Help & About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appIdentity: some View {
        Section {
            HStack(spacing: AppSpacing.medium) {
                Image("iWatchLogo")
                    .resizable().scaledToFit().frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text("iWatch").font(.headline)
                    Text("Version \(version) (\(build))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, AppSpacing.small)
            .accessibilityElement(children: .combine)
        }
    }

}

struct AcknowledgmentsView: View {
    var body: some View {
        List {
            Section {
                Link(destination: URL(string: "https://www.themoviedb.org/")!) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image("TMDBLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80)
                            .accessibilityHidden(true)

                        Label("The Movie Database (TMDB)", systemImage: "arrow.up.right.square")
                    }
                }
            } header: {
                Text("Data & Attribution")
            } footer: {
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
            }

            Section {
                Link(destination: URL(string: "https://trakt.tv/")!) {
                    Label("Trakt", systemImage: "arrow.up.right.square")
                }
            } footer: {
                Text("iWatch uses Trakt but is not endorsed or certified by Trakt.")
            }

            Section {
                Text("© 2026 Tyler Keegan. All rights reserved.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("Acknowledgments")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

#Preview {
    let container = AppContainer.preview()
    NavigationStack { AboutView() }.environment(container.session)
}
