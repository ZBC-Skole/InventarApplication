//
//  EquipmentCategory.swift
//  InventarApplication
//

import Foundation
import SwiftData

/// A user-editable grouping of equipment, e.g. "Bærbare" or "Kameraer".
@Model
final class EquipmentCategory {
    #Unique<EquipmentCategory>([\.name])

    var name: String
    /// SF Symbol shown next to the category in lists and filters.
    var symbolName: String
    var createdAt: Date

    /// Deleting a category keeps its equipment but leaves it uncategorized.
    @Relationship(deleteRule: .nullify, inverse: \Equipment.category)
    var equipment: [Equipment] = []

    init(
        name: String,
        symbolName: String = "shippingbox.fill",
        createdAt: Date = .now
    ) {
        self.name = name
        self.symbolName = symbolName
        self.createdAt = createdAt
    }
}

extension EquipmentCategory {
    /// Categories created on first launch so the app is usable straight away.
    static let defaults: [(name: String, symbolName: String)] = [
        ("Bærbare", "laptopcomputer"),
        ("Skærme", "display"),
        ("Tilbehør", "keyboard.fill"),
        ("Kameraer", "camera.fill"),
        ("Lyd", "headphones"),
        ("Netværk", "wifi.router.fill"),
        ("Værktøj", "hammer.fill"),
        ("Andet", "shippingbox.fill"),
    ]
}
