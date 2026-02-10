//
//  BrowserApp.swift
//  Browser
//
//  Created by Justin Gurtz on 2/7/26.
//

import SwiftUI

@main
struct BrowserApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
