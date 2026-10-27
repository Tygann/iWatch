//
//  iWatchApp.swift
//  iWatch
//
//  Created by Tyler Keegan on 8/15/25.
//

import BackgroundTasks
import SwiftUI

@main
struct iWatchApp: App {
    @UIApplicationDelegateAdaptor(ReleaseNotificationAppDelegate.self) private var appDelegate
    @State private var startup = AppStartupController()

    @AppStorage("appTheme") private var appTheme: AppTheme = .system

     var body: some Scene {
         WindowGroup {
             AppStartupView(startup: startup)
                 .appTheme(appTheme)
                 .modifier(UITestDynamicType())
         }
         .backgroundTask(.appRefresh(BackgroundRefresh.appRefreshIdentifier)) {
             await startup.open()
             guard let container = await startup.container else { return }
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
