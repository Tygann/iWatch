//
//  iWatchApp.swift
//  iWatch
//
//  Created by Tyler Keegan on 8/15/25.
//

import SwiftUI
import SwiftData

@main
struct iWatchApp: App {
    @State private var appEnv = AppEnvironment.makeDefault()

    init() {
        let _ = Secrets.tmdbAPIKey
        print("✅ TMDB key loaded")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
//                .environment(appEnv)
                .environmentObject(appEnv)
        }
        .modelContainer(appEnv.modelContainer)
    }
}
