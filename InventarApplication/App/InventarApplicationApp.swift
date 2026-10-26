//
//  InventarApplicationApp.swift
//  InventarApplication
//
//  Created by Patrick Jakobsen on 26/10/2026.
//

import SwiftData
import SwiftUI

@main
struct InventarApplicationApp: App {
    private let modelContainer = InventoryStore.makeContainer()

    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .modelContainer(modelContainer)
    }
}
