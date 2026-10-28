import SwiftUI

// MARK: - About Screen

struct AboutView: View {
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
                }
                NavigationLink {
                    AcknowledgmentsView()
                } label: {
                    SettingsNavigationLabel(title: "Acknowledgments", systemImage: "info.circle")
                }
            }
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
