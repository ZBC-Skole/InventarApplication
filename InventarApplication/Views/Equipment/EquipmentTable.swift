//
//  EquipmentTable.swift
//  InventarApplication
//

import SwiftData
import SwiftUI

/// The searchable, filterable, sortable list of equipment (Krav 1 and 5).
struct EquipmentTable: View {
    @Binding var selection: PersistentIdentifier?
    @Binding var sortOrder: [SortDescriptor<Equipment>]
    let isFiltering: Bool
    let searchText: String
    var onCreate: () -> Void
    var onEdit: (Equipment) -> Void
    var onDelete: (Equipment) -> Void

    @Query private var equipment: [Equipment]

    init(
        searchText: String,
        categoryName: String?,
        status: EquipmentStatus?,
        selection: Binding<PersistentIdentifier?>,
        sortOrder: Binding<[SortDescriptor<Equipment>]>,
        onCreate: @escaping () -> Void,
        onEdit: @escaping (Equipment) -> Void,
        onDelete: @escaping (Equipment) -> Void
    ) {
        _equipment = Query(
            filter: Equipment.predicate(
                searchText: searchText,
                categoryName: categoryName,
                status: status
            ),
            sort: sortOrder.wrappedValue,
            animation: .default
        )
        _selection = selection
        _sortOrder = sortOrder
        self.searchText = searchText
        self.isFiltering =
            !searchText.isEmpty || categoryName != nil || status != nil
        self.onCreate = onCreate
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    var body: some View {
        Table(equipment, selection: $selection, sortOrder: $sortOrder) {
            TableColumn(
                "Navn",
                sortUsing: SortDescriptor(
                    \Equipment.name,
                    comparator: .localizedStandard
                )
            ) { item in
                HStack(spacing: 10) {
                    EquipmentThumbnail(
                        imageData: item.thumbnailData,
                        symbolName: item.placeholderSymbolName
                    )
                    Text(item.name)
                        .fontWeight(.medium)
                }
            }
            .width(min: 160, ideal: 240)

            TableColumn("Kategori") { item in
                if let category = item.category {
                    Text(category.name)
                } else {
                    Text("Ingen")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: 90, ideal: 120)

            TableColumn(
                "Serienummer",
                sortUsing: SortDescriptor(
                    \Equipment.serialNumber,
                    comparator: .localizedStandard
                )
            ) { item in
                Text(item.serialNumber)
                    .monospaced()
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 150)

            TableColumn(
                "Status",
                sortUsing: SortDescriptor(\Equipment.statusRawValue)
            ) { item in
                StatusBadge(status: item.status)
            }
            .width(min: 100, ideal: 130)
        }
        .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
            if let item = item(for: ids) {
                Button("Rediger…", systemImage: "pencil") { onEdit(item) }
                Divider()
                Button("Slet…", systemImage: "trash", role: .destructive) {
                    onDelete(item)
                }
            } else {
                Button("Nyt udstyr…", systemImage: "plus", action: onCreate)
            }
        } primaryAction: { ids in
            if let item = item(for: ids) { onEdit(item) }
        }
        .onDeleteCommand {
            if let item = item(for: Set([selection].compactMap { $0 })) {
                onDelete(item)
            }
        }
        .overlay {
            if equipment.isEmpty {
                emptyState
            }
        }
        .navigationSubtitle(subtitle)
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if isFiltering {
            ContentUnavailableView(
                "Intet udstyr matcher",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text(
                    "Prøv at vælge en anden kategori eller status."
                )
            )
        } else {
            ContentUnavailableView {
                Label("Intet udstyr endnu", systemImage: "shippingbox")
            } description: {
                Text("Registrér dit første udstyr for at komme i gang.")
            } actions: {
                Button("Nyt udstyr", systemImage: "plus", action: onCreate)
                    .buttonStyle(.glassProminent)
            }
        }
    }

    private var subtitle: String {
        equipment.count == 1 ? "1 genstand" : "\(equipment.count) genstande"
    }

    private func item(for ids: Set<PersistentIdentifier>) -> Equipment? {
        guard let id = ids.first else { return nil }
        return equipment.first { $0.persistentModelID == id }
    }
}
