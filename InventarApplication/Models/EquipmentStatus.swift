//
//  EquipmentStatus.swift
//  InventarApplication
//

import Foundation

/// The lifecycle state of a piece of equipment.
///
/// Stored on `Equipment` as its raw value so it can be used in `#Predicate` filters.
nonisolated enum EquipmentStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case available
    case inUse
    case inRepair
    case retired

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .available: "Tilgængelig"
        case .inUse: "Udlånt"
        case .inRepair: "Til reparation"
        case .retired: "Kasseret"
        }
    }

    var symbolName: String {
        switch self {
        case .available: "checkmark.circle.fill"
        case .inUse: "person.crop.circle.fill"
        case .inRepair: "wrench.and.screwdriver.fill"
        case .retired: "archivebox.fill"
        }
    }
}
