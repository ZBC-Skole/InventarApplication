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
    /// Launch with `-UseSampleData` to try the app on an in-memory store with sample equipment.
    private let modelContainer =
        CommandLine.arguments.contains("-UseSampleData")
        ? InventoryStore.makePreviewContainer()
        : InventoryStore.makeContainer()

    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1240, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                WindowActionButton("Nyt udstyr…", action: \.newEquipmentAction)
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                WindowActionButton("Søg…", action: \.findAction)
                    .keyboardShortcut("f")
            }
            SidebarCommands()
            ImportFromDevicesCommands()
        }
    }
}

/// A menu item that runs a `WindowAction` in the focused window.
private struct WindowActionButton: View {
    let title: LocalizedStringKey
    @FocusedValue private var action: WindowAction?

    init(_ title: LocalizedStringKey, action: KeyPath<FocusedValues, WindowAction?>) {
        self.title = title
        _action = FocusedValue(action)
    }

    var body: some View {
        Button(title) { action?() }
            .disabled(action == nil)
    }
}
