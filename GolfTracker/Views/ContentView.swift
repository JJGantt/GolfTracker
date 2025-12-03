//
//  ContentView.swift
//  GolfTracker
//
//  Created by Jared gantt on 12/2/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: DataStore

    var body: some View {
        CourseListView(store: store)
    }
}

#Preview {
    ContentView()
        .environmentObject(DataStore())
}
