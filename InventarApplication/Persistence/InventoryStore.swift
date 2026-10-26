//
//  InventoryStore.swift
//  InventarApplication
//

import Foundation
import SwiftData

/// Builds the app's `ModelContainer`s.
enum InventoryStore {
    /// The on-disk container used by the running app.
    static func makeContainer() -> ModelContainer {
        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: InventorySchemaV1.self),
                migrationPlan: InventoryMigrationPlan.self,
                configurations: ModelConfiguration("Inventar")
            )
            try seedDefaultCategoriesIfNeeded(in: container.mainContext)
            return container
        } catch {
            fatalError("Could not open the inventory store: \(error)")
        }
    }

    /// An in-memory container filled with sample data, for SwiftUI previews.
    static func makePreviewContainer() -> ModelContainer {
        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: InventorySchemaV1.self),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            try seedDefaultCategoriesIfNeeded(in: container.mainContext)
            try insertSampleEquipment(in: container.mainContext)
            return container
        } catch {
            fatalError("Could not create the preview store: \(error)")
        }
    }

    /// Inserts `EquipmentCategory.defaults` the first time the store is opened.
    static func seedDefaultCategoriesIfNeeded(in context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<EquipmentCategory>()) == 0
        else { return }
        for category in EquipmentCategory.defaults {
            context.insert(
                EquipmentCategory(
                    name: category.name,
                    symbolName: category.symbolName
                )
            )
        }
        try context.save()
    }

    private static func insertSampleEquipment(in context: ModelContext) throws {
        let categories = try context.fetch(FetchDescriptor<EquipmentCategory>())
        func category(_ name: String) -> EquipmentCategory? {
            categories.first { $0.name == name }
        }

        let samples: [Equipment] = [
            Equipment(
                name: "MacBook Pro 14\"",
                serialNumber: "C02XK1JHMD6T",
                category: category("Bærbare"),
                status: .inUse
            ),
            Equipment(
                name: "MacBook Air 13\"",
                serialNumber: "FVFG3LL7Q6L4",
                category: category("Bærbare")
            ),
            Equipment(
                name: "Studio Display",
                serialNumber: "H4TFK0A2Q6X1",
                category: category("Skærme")
            ),
            Equipment(
                name: "Magic Keyboard",
                serialNumber: "F0T1302ADJ8M",
                category: category("Tilbehør")
            ),
            Equipment(
                name: "Sony A7 IV",
                serialNumber: "SN-4471902",
                category: category("Kameraer"),
                status: .inRepair,
                notes: "Udløserknappen sidder fast."
            ),
            Equipment(
                name: "AirPods Max",
                serialNumber: "GX7DL2Q1P73R",
                category: category("Lyd"),
                status: .inUse
            ),
            Equipment(
                name: "UniFi Dream Machine",
                serialNumber: "UDM-7A1B2C",
                category: category("Netværk")
            ),
            Equipment(
                name: "Gammel Dell-skærm",
                serialNumber: "CN-0F525M-74261",
                category: category("Skærme"),
                status: .retired
            ),
        ]
        samples.forEach(context.insert)
        try context.save()
    }
}
