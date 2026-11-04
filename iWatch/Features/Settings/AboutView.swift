import SwiftUI
import UIKit

// MARK: - About Screen

struct AboutView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var creditsSpacing: CGFloat = 0

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        aboutList
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
    }

    private var aboutList: some View {
        List {
            Section {
                appIdentity
            }
            .listRowBackground(Color.clear)

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

            Section {
                creditsSection
                    .padding(.top, creditsSpacing)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .onScrollGeometryChange(for: ListMetrics.self) { geometry in
            ListMetrics(
                availableHeight: geometry.containerSize.height
                    - geometry.contentInsets.top - geometry.contentInsets.bottom,
                contentHeight: geometry.contentSize.height
            )
        } action: { _, metrics in
            // Subtract the space already rendered before measuring unused height.
            let naturalHeight = metrics.contentHeight - creditsSpacing
            let spacing = max(0, (metrics.availableHeight - naturalHeight).rounded(.down))
            if abs(creditsSpacing - spacing) >= 1 {
                creditsSpacing = spacing
            }
        }
    }

    private struct ListMetrics: Equatable {
        var availableHeight: CGFloat
        var contentHeight: CGFloat
    }

    private var creditsSection: some View {
        VStack {
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
                        Spacer(minLength: 0)
                        traktLink
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            Text("iWatch is not endorsed or certified by TMDB or Trakt.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var tmdbLink: some View {
        Link(destination: URL(string: "https://www.themoviedb.org/")!) {
            Image("TMDBLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 28)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("The Movie Database (TMDB)")
        .accessibilityHint("Opens the TMDB website")
    }

    private var traktLink: some View {
        Link(destination: URL(string: "https://trakt.tv/")!) {
            Image("TraktLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .frame(width: 44, height: 44, alignment: typeSize.isAccessibilitySize ? .center : .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Trakt")
        .accessibilityHint("Opens the Trakt website")
    }

    private var appIdentity: some View {
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
        .accessibilityIdentifier("about-app-identity")
        .contextMenu {
            Button("Copy Version", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = "iWatch \(version) (\(build))"
            }
        }
    }

}
// MARK: - Previews

#Preview {
    let container = AppContainer.preview()
    NavigationStack { AboutView() }.environment(container.session)
}
