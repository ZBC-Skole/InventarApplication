//
//  EquipmentFormView.swift
//  InventarApplication
//

import SwiftData
import SwiftUI

/// Whether the form creates a new item or edits an existing one.
enum EquipmentFormMode: Identifiable {
    case create(categoryName: String?)
    case edit(Equipment)

    var id: AnyHashable {
        switch self {
        case .create: "create"
        case .edit(let equipment): equipment.persistentModelID
        }
    }
}

/// Sheet for creating (Krav 2) and editing (Krav 4) equipment.
struct EquipmentFormView: View {
    let mode: EquipmentFormMode
    var onSave: (Equipment) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \EquipmentCategory.name) private var categories: [EquipmentCategory]

    @State private var draft: EquipmentDraft
    @State private var showsValidationErrors = false
    @State private var saveError: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case name, serialNumber
    }

    init(mode: EquipmentFormMode, onSave: @escaping (Equipment) -> Void = { _ in }) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .create: _draft = State(initialValue: EquipmentDraft())
        case .edit(let equipment): _draft = State(initialValue: EquipmentDraft(equipment))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    EquipmentImagePicker(draft: $draft)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                }

                Section {
                    validatedField(
                        "Navn",
                        text: $draft.name,
                        prompt: "F.eks. MacBook Pro 14\"",
                        error: .emptyName,
                        field: .name
                    )
                    validatedField(
                        "Serienummer",
                        text: $draft.serialNumber,
                        prompt: "F.eks. C02XK1JHMD6T",
                        error: .emptySerialNumber,
                        field: .serialNumber,
                        isMonospaced: true
                    )
                }

                Section {
                    Picker("Kategori", selection: $draft.category) {
                        Text("Ingen").tag(EquipmentCategory?.none)
                        Divider()
                        ForEach(categories) { category in
                            Label(category.name, systemImage: category.symbolName)
                                .tag(Optional(category))
                        }
                    }
                    Picker("Status", selection: $draft.status) {
                        ForEach(EquipmentStatus.allCases) { status in
                            Label {
                                Text(status.title)
                            } icon: {
                                Image(systemName: status.symbolName)
                            }
                            .tag(status)
                        }
                    }
                }

                Section("Noter") {
                    TextField("Noter", text: $draft.notes, prompt: Text("Valgfrit"), axis: .vertical)
                        .lineLimit(3...8)
                        .labelsHidden()
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuller", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Opret" : "Gem", action: save)
                        .buttonStyle(.glassProminent)
                }
            }
            .alert(
                "Kunne ikke gemme",
                isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
            ) {
                Button("OK") {}
            } message: {
                Text(saveError ?? "")
            }
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 640, idealHeight: 720)
        .onAppear {
            if case .create(let categoryName?) = mode {
                draft.category = categories.first { $0.name == categoryName }
            }
            focusedField = .name
        }
    }

    private func validatedField(
        _ title: LocalizedStringKey,
        text: Binding<String>,
        prompt: LocalizedStringKey,
        error: EquipmentDraft.ValidationError,
        field: Field,
        isMonospaced: Bool = false
    ) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            TextField(title, text: text, prompt: Text(prompt))
                .focused($focusedField, equals: field)
                .monospaced(isMonospaced)
            if showsValidationErrors && draft.validationErrors.contains(error) {
                Label {
                    Text(error.message)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                }
                .font(.caption)
                .foregroundStyle(.red)
                .transition(.opacity)
            }
        }
        .animation(.smooth, value: draft.validationErrors)
    }

    private var isCreating: Bool {
        if case .create = mode { true } else { false }
    }

    private var title: String {
        switch mode {
        case .create: "Nyt udstyr"
        case .edit(let equipment): "Rediger \(equipment.name)"
        }
    }

    private func save() {
        guard draft.isValid else {
            showsValidationErrors = true
            if draft.validationErrors.contains(.emptyName) {
                focusedField = .name
            } else {
                focusedField = .serialNumber
            }
            return
        }

        let equipment: Equipment
        switch mode {
        case .create:
            guard let newEquipment = draft.makeEquipment() else { return }
            modelContext.insert(newEquipment)
            equipment = newEquipment
        case .edit(let existing):
            draft.apply(to: existing)
            equipment = existing
        }

        do {
            try modelContext.save()
            onSave(equipment)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

#Preview("Opret") {
    EquipmentFormView(mode: .create(categoryName: "Bærbare"))
        .modelContainer(InventoryStore.makePreviewContainer())
}
