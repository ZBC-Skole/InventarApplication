//
//  EquipmentDraft.swift
//  InventarApplication
//

import Foundation

/// An editable, unsaved copy of an `Equipment`'s fields.
///
/// Create and edit forms bind to a draft so that "Cancel" discards changes,
/// and validation (Krav 2) runs before anything touches the store.
struct EquipmentDraft: Equatable {
    var name = ""
    var serialNumber = ""
    var category: EquipmentCategory?
    var status: EquipmentStatus = .available
    var notes = ""
    var photoData: Data?
    var cutoutData: Data?

    enum ValidationError: Error, Equatable {
        case emptyName
        case emptySerialNumber

        var message: LocalizedStringResource {
            switch self {
            case .emptyName: "Name must not be empty."
            case .emptySerialNumber: "Serial number must not be empty."
            }
        }
    }

    init() {}

    init(_ equipment: Equipment) {
        name = equipment.name
        serialNumber = equipment.serialNumber
        category = equipment.category
        status = equipment.status
        notes = equipment.notes
        photoData = equipment.photoData
        cutoutData = equipment.cutoutData
    }

    var validationErrors: [ValidationError] {
        var errors: [ValidationError] = []
        if trimmedName.isEmpty { errors.append(.emptyName) }
        if trimmedSerialNumber.isEmpty { errors.append(.emptySerialNumber) }
        return errors
    }

    var isValid: Bool { validationErrors.isEmpty }

    /// Creates a new `Equipment` from the draft. Returns `nil` if the draft is invalid.
    func makeEquipment() -> Equipment? {
        guard isValid else { return nil }
        return Equipment(
            name: trimmedName,
            serialNumber: trimmedSerialNumber,
            category: category,
            status: status,
            notes: notes,
            photoData: photoData,
            cutoutData: cutoutData
        )
    }

    /// Writes the draft back to an existing `Equipment`. Returns `false` if the draft is invalid.
    @discardableResult
    func apply(to equipment: Equipment) -> Bool {
        guard isValid else { return false }
        equipment.name = trimmedName
        equipment.serialNumber = trimmedSerialNumber
        equipment.category = category
        equipment.status = status
        equipment.notes = notes
        equipment.photoData = photoData
        equipment.cutoutData = cutoutData
        equipment.updatedAt = .now
        return true
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedSerialNumber: String { serialNumber.trimmingCharacters(in: .whitespacesAndNewlines) }
}
