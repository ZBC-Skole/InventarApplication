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
        /// `previous` is the draft from before filling, so the user can undo it;
        /// `applied` holds only the suggestions that were actually filled in.
        case filled(previous: EquipmentDraft, applied: EquipmentSuggestion)
        case nothingFound(remarks: [String])
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
                        field: .name,
                        autofillSource: autofillSource(\.name, matches: draft.name)
                    )
                    validatedField(
                        "Serienummer",
                        text: $draft.serialNumber,
                        prompt: autofill == .running ? "Udfylder…" : "F.eks. C02XK1JHMD6T",
                        error: .emptySerialNumber,
                        field: .serialNumber,
                        isMonospaced: true,
                        autofillSource: autofillSource(\.serialNumber, matches: draft.serialNumber)
                    )
                }

                Section {
                    Picker(selection: $draft.category) {
                        Text("Ingen").tag(EquipmentCategory?.none)
                        Divider()
                        ForEach(categories) { category in
                            Label(category.name, systemImage: category.symbolName)
                                .tag(Optional(category))
                        }
                    } label: {
                        fieldLabel(
                            "Kategori",
                            autofillSource: autofillSource(\.categoryName, matches: draft.category?.name ?? "")
                        )
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

                Section {
                    TextField("Noter", text: $draft.notes, prompt: Text("Valgfrit"), axis: .vertical)
                        .lineLimit(3...8)
                        .labelsHidden()
                } header: {
                    fieldLabel("Noter", autofillSource: autofillSource(\.notes, matches: draft.notes))
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
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            switch autofill {
            case .idle:
                EmptyView()
            case .running:
                ProgressView()
                    .controlSize(.small)
                Text("Apple Intelligence læser billedet…")
                    .foregroundStyle(.secondary)
            case .filled(let previous, let applied):
                Image(systemName: "sparkles")
                    .foregroundStyle(.intelligenceGradient)
                VStack(alignment: .leading, spacing: 4) {
                    Text(filledSummary(applied))
                    remarksList(applied.remarks)
                }
                Spacer()
                Button("Fortryd") { undoAutofill(restoring: previous) }
                    .buttonStyle(.glass)
            case .nothingFound(let remarks):
                Image(systemName: "sparkles")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Intet blev udfyldt, fordi intet kunne aflæses sikkert.")
                    remarksList(remarks)
                }
            case .failed:
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Text("Billedet kunne ikke aflæses automatisk.")
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    private func remarksList(_ remarks: [String]) -> some View {
        ForEach(remarks, id: \.self) { remark in
            Text(remark)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func filledSummary(_ applied: EquipmentSuggestion) -> String {
        let count = [applied.name, applied.serialNumber, applied.categoryName, applied.notes]
            .compactMap(\.self).count
        let fields = count == 1 ? "1 felt" : "\(count) felter"
        return "\(fields) udfyldt ud fra billedet. Hold markøren over ✨ for at se hvorfor."
    }

    /// Why a field was filled in, as long as the user hasn't changed it since.
    private func autofillSource(
        _ field: KeyPath<EquipmentSuggestion, SuggestedValue?>,
        matches currentValue: String
    ) -> String? {
        guard case .filled(_, let applied) = autofill,
            let suggested = applied[keyPath: field],
            suggested.value == currentValue
        else { return nil }
        return suggested.source
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

    /// Fills in the fields that are still empty. Anything the user has typed is kept.
    private func apply(_ suggestion: EquipmentSuggestion) {
        let previous = draft
        var applied = EquipmentSuggestion(remarks: suggestion.remarks)

        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty, let name = suggestion.name {
            draft.name = name.value
            applied.name = name
        }
        if draft.serialNumber.trimmingCharacters(in: .whitespaces).isEmpty,
            let serialNumber = suggestion.serialNumber
        {
            draft.serialNumber = serialNumber.value
            applied.serialNumber = serialNumber
        }
        if draft.category == nil,
            let categoryName = suggestion.categoryName,
            let category = categories.first(where: { $0.name == categoryName.value })
        {
            draft.category = category
            applied.categoryName = categoryName
        }
        if draft.notes.trimmingCharacters(in: .whitespaces).isEmpty, let notes = suggestion.notes {
            draft.notes = notes.value
            applied.notes = notes
        }

        let didFill = [applied.name, applied.serialNumber, applied.categoryName, applied.notes]
            .contains { $0 != nil }
        autofill = didFill
            ? .filled(previous: previous, applied: applied)
            : .nothingFound(remarks: suggestion.remarks)
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
        isMonospaced: Bool = false,
        autofillSource: String? = nil
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
                fieldLabel(title, autofillSource: autofillSource)
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

    /// A field title, marked with ✨ when its value came from the photo.
    private func fieldLabel(_ title: LocalizedStringKey, autofillSource: String?) -> some View {
        HStack(spacing: 4) {
            Text(title)
            if let autofillSource {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.intelligenceGradient)
                    .help(autofillSource)
                    .accessibilityLabel("Udfyldt ud fra billedet: \(autofillSource)")
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.smooth, value: autofillSource)
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
