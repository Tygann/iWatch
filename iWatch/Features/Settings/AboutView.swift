import SwiftUI

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
                    Label("The Movie Database (TMDB)", systemImage: "arrow.up.right.square")
                }
            } header: {
                Text("Data & Attribution")
            } footer: {
                Text("Movie and television metadata is provided by TMDB. iWatch is not endorsed or certified by TMDB.")
            }

            Section {
                Text("© 2026 iWatch. All rights reserved.")
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

#Preview {
    NavigationStack {
        AboutView()
    }
}
