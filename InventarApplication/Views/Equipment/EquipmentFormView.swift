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
    @State private var autofill = AutofillState.idle
    @State private var autofillTask: Task<Void, Never>?
    @FocusState private var focusedField: Field?

    private enum Field {
        case name, serialNumber
    }

    /// Progress of filling the form in from the photo with Apple Intelligence.
    private enum AutofillState: Equatable {
        case idle
        case running
        /// Holds the draft from before filling, so the user can undo it.
        case filled(previous: EquipmentDraft)
        case nothingFound
        case failed
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
                    EquipmentImagePicker(draft: $draft, onImageImported: autofill(from:))
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    if autofill != .idle {
                        autofillStatus
                    }
                }

                Section {
                    validatedField(
                        "Navn",
                        text: $draft.name,
                        prompt: autofill == .running ? "Udfylder…" : "F.eks. MacBook Pro 14\"",
                        error: .emptyName,
                        field: .name
                    )
                    validatedField(
                        "Serienummer",
                        text: $draft.serialNumber,
                        prompt: autofill == .running ? "Udfylder…" : "F.eks. C02XK1JHMD6T",
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
            EquipmentAutofill.prewarm()
        }
        .onChange(of: draft.photoData == nil) { _, hasNoPhoto in
            if hasNoPhoto { cancelAutofill() }
        }
        .onDisappear(perform: cancelAutofill)
    }

    // MARK: - Autofill

    @ViewBuilder
    private var autofillStatus: some View {
        HStack(spacing: 8) {
            switch autofill {
            case .idle:
                EmptyView()
            case .running:
                ProgressView()
                    .controlSize(.small)
                Text("Apple Intelligence udfylder formularen ud fra billedet…")
                    .foregroundStyle(.secondary)
            case .filled(let previous):
                Label {
                    Text("Udfyldt ud fra billedet. Tjek felterne, før du gemmer.")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.intelligenceGradient)
                }
                Spacer()
                Button("Fortryd") { undoAutofill(restoring: previous) }
                    .buttonStyle(.glass)
            case .nothingFound:
                Label("Der blev ikke genkendt noget at udfylde.", systemImage: "sparkles")
                    .foregroundStyle(.secondary)
            case .failed:
                Label("Formularen kunne ikke udfyldes automatisk.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    /// Asks the on-device model for suggestions and fills in the fields that are still empty.
    private func autofill(from photoData: Data) {
        autofillTask?.cancel()
        guard EquipmentAutofill.isAvailable else { return }

        withAnimation { autofill = .running }
        let categoryNames = categories.map(\.name)
        autofillTask = Task {
            do {
                let suggestion = try await EquipmentAutofill.suggest(
                    from: photoData,
                    categoryNames: categoryNames
                )
                guard !Task.isCancelled, draft.photoData == photoData else { return }
                withAnimation { apply(suggestion) }
            } catch {
                guard !Task.isCancelled else { return }
                withAnimation { autofill = .failed }
            }
        }
    }

    private func apply(_ suggestion: EquipmentSuggestion) {
        let previous = draft
        var didFill = false

        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty, let name = suggestion.name {
            draft.name = name
            didFill = true
        }
        if draft.serialNumber.trimmingCharacters(in: .whitespaces).isEmpty,
            let serialNumber = suggestion.serialNumber
        {
            draft.serialNumber = serialNumber
            didFill = true
        }
        if draft.category == nil,
            let categoryName = suggestion.categoryName,
            let category = categories.first(where: { $0.name == categoryName })
        {
            draft.category = category
            didFill = true
        }
        if draft.notes.trimmingCharacters(in: .whitespaces).isEmpty, let notes = suggestion.notes {
            draft.notes = notes
            didFill = true
        }

        autofill = didFill ? .filled(previous: previous) : .nothingFound
    }

    private func undoAutofill(restoring previous: EquipmentDraft) {
        withAnimation {
            draft.name = previous.name
            draft.serialNumber = previous.serialNumber
            draft.category = previous.category
            draft.notes = previous.notes
            autofill = .idle
        }
    }

    private func cancelAutofill() {
        autofillTask?.cancel()
        autofillTask = nil
        autofill = .idle
    }

    // MARK: - Fields

    private func validatedField(
        _ title: LocalizedStringKey,
        text: Binding<String>,
        prompt: LocalizedStringKey,
        error: EquipmentDraft.ValidationError,
        field: Field,
        isMonospaced: Bool = false
    ) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            // A separate label keeps it in the default font when the field is monospaced.
            LabeledContent {
                TextField(title, text: text, prompt: Text(prompt))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospaced(isMonospaced)
                    .focused($focusedField, equals: field)
            } label: {
                Text(title)
            }
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
