//
//  GolfTrackerApp.swift
//  GolfTracker
//
//  Created by Jared gantt on 12/2/25.
//

import SwiftUI

@main
struct GolfTrackerApp: App {
    @StateObject private var store = DataStore()

    init() {
        print("🚀🚀🚀 APP LAUNCHED - GolfTracker is starting! 🚀🚀🚀")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
