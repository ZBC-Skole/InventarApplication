//
//  MainView.swift
//  InventarApplication
//

import SwiftData
import SwiftUI

/// The main window: categories, the equipment table and the detail panel.
struct MainView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var sidebarSelection: SidebarFilter? = .all
    @State private var statusFilter: EquipmentStatus?
    @State private var searchText = ""
    @State private var sortOrder = Equipment.defaultSort
    @State private var selection: PersistentIdentifier?
    @State private var formMode: EquipmentFormMode?
    @State private var pendingDeletion: Equipment?
    @State private var windowID = UUID()
    @State private var isInspectorPresented = true
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: {
            EquipmentTable(
                searchText: searchText,
                categoryName: sidebarSelection?.categoryName,
                status: statusFilter,
                selection: $selection,
                sortOrder: $sortOrder,
                onCreate: createEquipment,
                onEdit: { formMode = .edit($0) },
                onDelete: { pendingDeletion = $0 }
            )
            .navigationTitle(sidebarSelection?.categoryName ?? "Alt udstyr")
            .searchable(text: $searchText, prompt: "Søg på navn eller serienummer")
            .searchFocused($isSearchFocused)
            .toolbar {
                ToolbarItem {
                    statusFilterMenu
                }
                ToolbarItem {
                    Button("Nyt udstyr", systemImage: "plus", action: createEquipment)
                        .help("Registrér nyt udstyr (⌘N)")
                }
                ToolbarSpacer(.fixed)
                ToolbarItem {
                    inspectorToggle
                }
            }
            .inspector(isPresented: $isInspectorPresented) {
                detailPanel
                    .inspectorColumnWidth(min: 320, ideal: 380, max: 560)
            }
        }
        .sheet(item: $formMode) { mode in
            EquipmentFormView(mode: mode) { saved in
                selection = saved.persistentModelID
            }
        }
        .alert(
            "Slet udstyr?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { equipment in
            Button("Slet", role: .destructive) { delete(equipment) }
            Button("Annuller", role: .cancel) {}
        } message: { equipment in
            Text("“\(equipment.name)” (\(equipment.serialNumber)) slettes permanent. Det kan ikke fortrydes.")
        }
        .focusedSceneValue(
            \.newEquipmentAction,
            WindowAction(windowID: windowID, perform: createEquipment)
        )
        .focusedSceneValue(
            \.findAction,
            WindowAction(windowID: windowID) { isSearchFocused = true }
        )
    }

    /// The detail panel (Krav 3), shown in the trailing inspector.
    @ViewBuilder
    private var detailPanel: some View {
        if let selectedEquipment {
            EquipmentDetailView(
                equipment: selectedEquipment,
                onEdit: { formMode = .edit(selectedEquipment) },
                onDelete: { pendingDeletion = selectedEquipment }
            )
        } else {
            ContentUnavailableView(
                "Intet valgt",
                systemImage: "shippingbox",
                description: Text("Vælg udstyr i tabellen for at se detaljerne.")
            )
        }
    }

    private var inspectorToggle: some View {
        Button("Detaljer", systemImage: "sidebar.trailing") {
            isInspectorPresented.toggle()
        }
        .help(isInspectorPresented ? "Skjul detaljer" : "Vis detaljer")
    }

    private var statusFilterMenu: some View {
        Menu {
            Picker("Status", selection: $statusFilter) {
                Text("Alle statusser").tag(EquipmentStatus?.none)
                Divider()
                ForEach(EquipmentStatus.allCases) { status in
                    Label {
                        Text(status.title)
                    } icon: {
                        Image(systemName: status.symbolName)
                    }
                    .tag(Optional(status))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(
                "Filtrér på status",
                systemImage: statusFilter == nil
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill"
            )
        }
        .help("Filtrér på status")
    }

    private var selectedEquipment: Equipment? {
        guard let selection else { return nil }
        return modelContext.model(for: selection) as? Equipment
    }

    private func createEquipment() {
        formMode = .create(categoryName: sidebarSelection?.categoryName)
    }

    private func delete(_ equipment: Equipment) {
        if selection == equipment.persistentModelID {
            selection = nil
        }
        modelContext.delete(equipment)
        try? modelContext.save()
    }
}

/// An action performed in a specific window, exposed to menu commands.
struct WindowAction: Equatable {
    /// Identifies the window, so the menu only refreshes when focus moves.
    let windowID: UUID
    let perform: () -> Void

    func callAsFunction() { perform() }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.windowID == rhs.windowID }
}

extension FocusedValues {
    /// Opens the "Nyt udstyr" sheet. Used by Arkiv ▸ Nyt udstyr (⌘N).
    @Entry var newEquipmentAction: WindowAction?
    /// Focuses the search field. Used by Rediger ▸ Søg (⌘F).
    @Entry var findAction: WindowAction?
}

#Preview {
    MainView()
        .modelContainer(InventoryStore.makePreviewContainer())
        .frame(width: 1200, height: 720)
}
