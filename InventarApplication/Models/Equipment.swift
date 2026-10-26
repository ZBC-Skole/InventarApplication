//
//  Equipment.swift
//  InventarApplication
//

import Foundation
import SwiftData

/// A single registered item in the inventory.
@Model
final class Equipment {
    #Index<Equipment>([\.name], [\.serialNumber], [\.statusRawValue])

    var name: String
    var serialNumber: String
    var notes: String
    var category: EquipmentCategory?
    var createdAt: Date
    var updatedAt: Date

    /// Backing storage for `status`. Kept as a plain string so it works in `#Predicate`.
    var statusRawValue: String

    /// The photo as the user imported or captured it.
    @Attribute(.externalStorage) var photoData: Data?
    /// The subject cut out from `photoData` (transparent PNG), when one could be found.
    @Attribute(.externalStorage) var cutoutData: Data?

    var status: EquipmentStatus {
        get { EquipmentStatus(rawValue: statusRawValue) ?? .available }
        set { statusRawValue = newValue.rawValue }
    }

    /// The image to show in the UI: the cutout if available, otherwise the original photo.
    var displayImageData: Data? { cutoutData ?? photoData }

    init(
        name: String,
        serialNumber: String,
        category: EquipmentCategory? = nil,
        status: EquipmentStatus = .available,
        notes: String = "",
        photoData: Data? = nil,
        cutoutData: Data? = nil,
        createdAt: Date = .now
    ) {
        self.name = name
        self.serialNumber = serialNumber
        self.category = category
        self.statusRawValue = status.rawValue
        self.notes = notes
        self.photoData = photoData
        self.cutoutData = cutoutData
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

// MARK: - Querying

extension Equipment {
    /// Builds the predicate for the search field and the category/status filters (Krav 5).
    ///
    /// - Parameters:
    ///   - searchText: Matches name or serial number, case- and diacritic-insensitive. Empty matches all.
    ///   - categoryName: Only equipment in this category. `nil` matches all.
    ///   - status: Only equipment with this status. `nil` matches all.
    static func predicate(
        searchText: String = "",
        categoryName: String? = nil,
        status: EquipmentStatus? = nil
    ) -> Predicate<Equipment> {
        let searchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filterByCategory = categoryName != nil
        let categoryName = categoryName ?? ""
        let filterByStatus = status != nil
        let statusRawValue = status?.rawValue ?? ""

        return #Predicate<Equipment> { item in
            (searchText.isEmpty
                || item.name.localizedStandardContains(searchText)
                || item.serialNumber.localizedStandardContains(searchText))
            && (!filterByCategory || item.category?.name == categoryName)
            && (!filterByStatus || item.statusRawValue == statusRawValue)
        }
    }

    static let defaultSort: [SortDescriptor<Equipment>] = [
        SortDescriptor(\.name, comparator: .localizedStandard),
    ]
}
