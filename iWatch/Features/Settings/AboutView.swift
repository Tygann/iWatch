import StoreKit
import SwiftUI

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

            Section("App") {
                LabeledContent("Version", value: version)
                LabeledContent("Build", value: build)

                Button {
                    requestReview()
                } label: {
                    Label("Rate iWatch", systemImage: "star")
                }
            }

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
        .navigationTitle("About iWatch")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appIdentity: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "sparkles.tv.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.blue.gradient)
                    .accessibilityHidden(true)

                Text("iWatch")
                    .font(.largeTitle.bold())

                Text("Track the movies and shows you care about.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .listRowBackground(Color.clear)
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
