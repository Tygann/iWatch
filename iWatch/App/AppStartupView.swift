import SwiftUI
import SwiftData

struct AppStartupView: View {
    @Bindable var startup: AppStartupController

    var body: some View {
        Group {
            if let container = startup.container {
                ReadyAppView(container: container)
            } else if let issue = startup.issue {
                LibraryRecoveryView(issue: issue) { Task { await startup.open() } }
            } else {
                ProgressView("Opening Library…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard startup.container == nil, startup.issue == nil else { return }
            await startup.open()
        }
    }
}

private struct ReadyAppView: View {
    @Environment(\.scenePhase) private var scenePhase
    let container: AppContainer

    var body: some View {
        ContentView()
            .environment(container)
            .environment(container.session)
            .environment(container.router)
            .modelContainer(container.persistence.modelContainer)
            .task {
                container.maintainMetadataCache()
                // Opening may finish after the scene's initial active transition.
                if scenePhase == .active { container.session.appDidBecomeActive() }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    container.maintainMetadataCache()
                    container.session.appDidBecomeActive()
                case .background: container.session.appDidEnterBackground()
                default: break
                }
            }
    }
}

struct LibraryRecoveryView: View {
    let issue: StoreOpeningIssue
    let retry: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    Label("Library Unavailable", systemImage: "externaldrive.badge.exclamationmark")
                        .font(.title2.bold())
                    Text(issue.message)
                    Text("iWatch hasn’t reset or replaced your library.")
                        .foregroundStyle(.secondary)
                    Button("Try Again", action: retry)
                        .buttonStyle(.borderedProminent)
                        .frame(minHeight: 44)
                    Link("Contact Support", destination: URL(string: "https://tylerkeegan.com/iwatch/support/")!)
                        .frame(minHeight: 44)
                    DisclosureGroup("Details") {
                        Text(issue.reference).font(.caption).textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.large)
            }
            .navigationTitle("iWatch")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
