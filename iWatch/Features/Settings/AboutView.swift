import SwiftUI

// MARK: - About Screen

struct AboutView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
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
                Text("Keep track of movies and shows, follow your watchlist, and pick up where you left off.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)

            Section {
                NavigationLink { SyncSupportView() } label: {
                    SettingsNavigationLabel(title: "Contact Support", systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("about-support")
            }

            Section {
                Link(destination: URL(string: "https://tylerkeegan.com/iwatch/privacy/")!) {
                    SettingsNavigationLabel(title: "Privacy Policy", systemImage: "hand.raised")
                        .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
            }
            creditsSection
            Section {
                Text("© 2026 Tyler Keegan. All rights reserved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var creditsSection: some View {
        Section {
            VStack {
                Text("Data & Integrations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if typeSize.isAccessibilitySize {
                    VStack {
                        tmdbLink
                        traktLink
                    }
                } else {
                    HStack {
                        tmdbLink
                        traktLink
                    }
                }
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("iWatch uses Trakt but is not endorsed or certified by Trakt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var tmdbLink: some View {
        Link(destination: URL(string: "https://www.themoviedb.org/")!) {
            Image("TMDBLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 44)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("The Movie Database (TMDB)")
        .accessibilityHint("Opens the TMDB website")
    }

    private var traktLink: some View {
        Link(destination: URL(string: "https://trakt.tv/")!) {
            HStack {
                Image("TraktLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                Text("Trakt").font(.headline).foregroundStyle(Color.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Trakt")
        .accessibilityHint("Opens the Trakt website")
    }

    private var appIdentity: some View {
        Section {
            VStack {
                Image("iWatchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .accessibilityHidden(true)
                Text("iWatch")
                    .font(.largeTitle.bold())
                Text("Version \(version) (\(build))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
        .listRowBackground(Color.clear)
    }

}
// MARK: - Previews

#Preview {
    let container = AppContainer.preview()
    NavigationStack { AboutView() }.environment(container.session)
}
