//
//  InventorySchema.swift
//  InventarApplication
//

import Foundation
import SwiftData

/// The first shipped version of the store schema.
///
/// When a model changes in a way SwiftData can't migrate on its own, add a
/// `InventorySchemaV2` and a stage to `InventoryMigrationPlan`.
enum InventorySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Equipment.self, EquipmentCategory.self]
    }
}

enum InventoryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [InventorySchemaV1.self]
    }

    static var stages: [MigrationStage] { [] }
}
