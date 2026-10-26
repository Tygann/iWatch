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

            Section("Privacy & Support") {
                Link(destination: URL(string: "https://tylerkeegan.com/iwatch/privacy/")!) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }

                Link(destination: URL(string: "https://tylerkeegan.com/iwatch/support/")!) {
                    Label("Support", systemImage: "questionmark.circle")
                }
            }

            Section {
                Text("© 2026 Tyler Keegan. All rights reserved.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appIdentity: some View {
        Section {
            VStack(spacing: 12) {
                Image("iWatchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)

                Text("iWatch")
                    .font(.largeTitle.bold())

                Text("Track the movies and shows you care about.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("Version \(version) (\(build))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
        }
        .listRowBackground(Color.clear)
    }

}

// MARK: - Previews

#Preview {
    NavigationStack {
        AboutView()
    }
}
