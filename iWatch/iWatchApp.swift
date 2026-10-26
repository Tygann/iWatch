//
//  iWatchApp.swift
//  iWatch
//
//  Created by Tyler Keegan on 8/15/25.
//

import BackgroundTasks
import SwiftUI
import SwiftData

@main
struct iWatchApp: App {
    @UIApplicationDelegateAdaptor(ReleaseNotificationAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var container = AppContainer.bootstrap()

    @AppStorage("appTheme") private var appTheme: AppTheme = .system

     var body: some Scene {
         WindowGroup {
             ContentView()
                 .environment(container)
                 .environment(container.session)
                 .environment(container.router)
                 .modelContainer(container.persistence.modelContainer)
                 .appTheme(appTheme)
                 .modifier(UITestDynamicType())
                 .task { container.maintainMetadataCache() }
                 .onChange(of: scenePhase) { _, phase in
                     switch phase {
                     case .active:
                         container.maintainMetadataCache()
                         container.session.appDidBecomeActive()
                     case .background:
                         container.session.appDidEnterBackground()
                     default:
                         break
                     }
                 }
         }
         .backgroundTask(.appRefresh(BackgroundRefresh.appRefreshIdentifier)) {
             await container.session.handleBackgroundRefresh()
             await container.releaseNotificationCoordinator.reconcile()
         }
     }
}

private struct UITestDynamicType: ViewModifier {
    func body(content: Content) -> some View {
        if ProcessInfo.processInfo.arguments.contains("UITEST_MODE"),
           ProcessInfo.processInfo.arguments.contains("UITEST_ACCESSIBILITY_TEXT") {
            content.environment(\.dynamicTypeSize, .accessibility5)
        } else {
            content
        }
    }
}
