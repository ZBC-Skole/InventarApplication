//
//  SidebarView.swift
//  InventarApplication
//

import SwiftData
import SwiftUI

/// What the sidebar narrows the table down to.
enum SidebarFilter: Hashable {
    case all
    case category(name: String)

    var categoryName: String? {
        switch self {
        case .all: nil
        case .category(let name): name
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarFilter?

    @Query(sort: \EquipmentCategory.name, order: .forward)
    private var categories: [EquipmentCategory]
    @Query private var equipment: [Equipment]

    var body: some View {
        List(selection: $selection) {
            Label("Alt udstyr", systemImage: "square.grid.2x2")
                .badge(equipment.count)
                .tag(SidebarFilter.all)

            Section("Kategorier") {
                ForEach(categories) { category in
                    Label(category.name, systemImage: category.symbolName)
                        .badge(category.equipment.count)
                        .tag(SidebarFilter.category(name: category.name))
                }
            }
        }
        .navigationTitle("Inventar")
    }
}

#Preview {
    NavigationSplitView {
        SidebarView(selection: .constant(.all))
    } detail: {
        EmptyView()
    }
    .modelContainer(InventoryStore.makePreviewContainer())
}
