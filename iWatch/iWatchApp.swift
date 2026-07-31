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
                 .onChange(of: scenePhase) { _, phase in
                     switch phase {
                     case .active:
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
         }
     }
}
