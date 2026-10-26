//
//  EquipmentAutofill.swift
//  InventarApplication
//

import CoreGraphics
import Foundation
import FoundationModels
import ImageIO
import Vision

/// A value suggested for one form field, and why it was suggested.
nonisolated struct SuggestedValue: Sendable, Equatable {
    var value: String
    /// Shown to the user, e.g. "Læst fra teksten på billedet."
    var source: String
}

/// Form values suggested from a photo. A `nil` field was left empty on purpose.
nonisolated struct EquipmentSuggestion: Sendable, Equatable {
    var name: SuggestedValue?
    var categoryName: SuggestedValue?
    var serialNumber: SuggestedValue?
    var notes: SuggestedValue?
    /// Why fields were left empty, shown to the user.
    var remarks: [String] = []
}

/// Suggests form values for a photo of equipment, entirely on device, without guessing.
///
/// Vision reads the text in the photo, and the Apple Intelligence foundation
/// model looks at the image and picks from fixed lists (item type, colour,
/// condition, category) wherever possible. Brand, model and serial number are
/// only kept when they can be found in the text, and anything the model isn't
/// sure about is left empty.
nonisolated enum EquipmentAutofill {
    enum Failure: Error {
        case unreadableImage
    }

    /// Whether the on-device model is ready and can look at images.
    static var isAvailable: Bool {
        let model = SystemLanguageModel.default
        return model.isAvailable && model.capabilities.contains(.vision)
    }

    /// Loads the model ahead of time, so the first suggestion doesn't wait
    /// for a cold start. Call when the user is about to add a photo.
    static func prewarm() {
        guard isAvailable else { return }
        LanguageModelSession(instructions: instructions).prewarm()
    }

    @concurrent
    static func suggest(
        from imageData: Data,
        categoryNames: [String]
    ) async throws -> EquipmentSuggestion {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Failure.unreadableImage }

        let evidence = TextEvidence(lines: (try? await recognizeText(in: image)) ?? [])

        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            schema: try schema(categoryNames: categoryNames),
            options: GenerationOptions(samplingMode: .greedy)
        ) {
            "Registrér udstyret på billedet."
            "Mulige kategorier: \(categoryNames.joined(separator: ", "))."
            evidence.promptDescription
            Attachment(image)
        }

        return suggestion(
            from: try Answer(response.content),
            evidence: evidence,
            categoryNames: categoryNames
        )
    }

    // MARK: - Turning the answer into suggestions

    /// The model's raw answer, before it is checked.
    struct Answer {
        var subject: String
        var itemType: String
        var brand: String
        var model: String
        var category: String
        var serialNumber: String
    }

    /// Keeps only what the photo backs up, and explains what was left out.
    static func suggestion(
        from answer: Answer,
        evidence: TextEvidence,
        categoryNames: [String]
    ) -> EquipmentSuggestion {
        var suggestion = EquipmentSuggestion()
        let readFromText = "Læst fra teksten på billedet."

        // Serial number: a labelled one in the text wins; otherwise the model's
        // pick, but only if it is written in the text.
        let serialNumber =
            evidence.labeledSerialNumber()
            ?? nonEmpty(answer.serialNumber).flatMap { candidate in
                TextEvidence.looksLikeSerialNumber(candidate)
                    && evidence.containsVerbatim(candidate)
                    && !evidence.isLabeledAsOtherIdentifier(candidate)
                    ? candidate : nil
            }
        if let serialNumber {
            suggestion.serialNumber = SuggestedValue(value: serialNumber, source: readFromText)
        } else {
            suggestion.remarks.append("Der kunne ikke læses et serienummer på billedet.")
        }

        // Everything else needs one clear item in the photo.
        switch answer.subject {
        case Subject.single:
            break
        case Subject.multiple:
            suggestion.remarks.append("Billedet viser flere genstande. Vælg et billede med kun én genstand.")
            return suggestion
        default:
            suggestion.remarks.append("Der er ingen tydelig genstand på billedet.")
            return suggestion
        }

        let itemType = answer.itemType == unknown ? nil : answer.itemType
        let brand = nonEmpty(answer.brand).flatMap { brand in
            evidence.contains(brand) && !TextEvidence.isOnlyLabelWords(brand) ? brand : nil
        }
        let model = modelName(answer.model, brand: brand, serialNumber: serialNumber)
            .flatMap { evidence.contains($0) ? $0 : nil }

        // Name: brand and model from the text, otherwise the kind of item.
        switch (brand, model, itemType) {
        case let (brand?, model?, _):
            suggestion.name = SuggestedValue(
                value: "\(brand) \(model)",
                source: "Mærke og model er læst fra teksten på billedet."
            )
        case let (brand?, nil, itemType):
            suggestion.name = SuggestedValue(
                value: itemType.map { "\(brand) \($0)" } ?? brand,
                source: "Mærket er læst fra teksten på billedet."
            )
        case let (nil, model?, itemType):
            suggestion.name = SuggestedValue(
                value: itemType.map { "\(capitalizedFirst($0)) \(model)" } ?? model,
                source: "Modellen er læst fra teksten på billedet."
            )
        case let (nil, nil, itemType?):
            suggestion.name = SuggestedValue(
                value: capitalizedFirst(itemType),
                source: "Genkendt ud fra billedet."
            )
            suggestion.remarks.append("Mærke og model står ikke på billedet, så de er ikke gættet.")
        case (nil, nil, nil):
            suggestion.remarks.append("Genstanden kunne ikke genkendes sikkert.")
        }

        // Category: only when the kind of item is known.
        if let itemType, answer.category != noCategory, categoryNames.contains(answer.category) {
            suggestion.categoryName = SuggestedValue(
                value: answer.category,
                source: "Valgt, fordi genstanden er genkendt som \(itemType)."
            )
        }

        // Notes: other text printed on the item, e.g. a model or part number.
        let usedValues = [brand, model, serialNumber].compactMap(\.self)
        let otherText = evidence.lines(notCoveredBy: usedValues).prefix(4)
        if !otherText.isEmpty {
            suggestion.notes = SuggestedValue(
                value: "Tekst på genstanden: " + otherText.joined(separator: ", "),
                source: readFromText
            )
        }

        return suggestion
    }

    // MARK: - Prompt

    private static let instructions = """
        Du hjælper med at registrere udstyr i et inventarsystem ud fra et foto.
        Gæt aldrig. Er du ikke sikker, så vælg "\(unknown)" eller lad teksten være tom.
        Mærke, model og serienummer må kun udfyldes, hvis de står i den tekst, \
        der kan læses på billedet. Et logo uden tekst tæller ikke.
        """

    private static let unknown = "ukendt"
    private static let noCategory = "Ingen"

    private enum Subject {
        static let single = "én tydelig genstand"
        static let multiple = "flere genstande"
        static let none = "ingen tydelig genstand"
    }

    private static let itemTypes = [
        "bærbar computer", "stationær computer", "skærm", "tablet", "mobiltelefon",
        "tastatur", "mus", "pegeplade", "headset", "hovedtelefoner", "høretelefoner",
        "højttaler", "mikrofon", "kamera", "objektiv", "webcam", "stativ", "projektor",
        "printer", "scanner", "router", "netværksswitch", "access point", "harddisk",
        "usb-stik", "hukommelseskort", "oplader", "strømforsyning", "kabel",
        "dockingstation", "smartwatch", "spillekonsol", "controller", "boremaskine",
        "skruetrækker", "værktøj", "lampe",
    ]

    private static func schema(categoryNames: [String]) throws -> GenerationSchema {
        let text = DynamicGenerationSchema(type: String.self)
        func choice(_ name: String, _ values: [String]) -> DynamicGenerationSchema {
            DynamicGenerationSchema(name: name, anyOf: values)
        }

        // Properties are generated in order: deciding what is in the photo
        // first keeps the later answers consistent with it.
        let root = DynamicGenerationSchema(
            name: "Udstyr",
            properties: [
                .init(
                    name: "subject",
                    description: "Hvad billedet viser.",
                    schema: choice("Motiv", [Subject.single, Subject.multiple, Subject.none])
                ),
                .init(
                    name: "itemType",
                    description: "Hvilken slags genstand det er. \"\(unknown)\" hvis du ikke er sikker.",
                    schema: choice("Genstandstype", itemTypes + [unknown])
                ),
                .init(
                    name: "brand",
                    description: "Mærket, kun hvis det står som tekst på billedet. Ellers tom tekst.",
                    schema: text
                ),
                .init(
                    name: "model",
                    description: "Modelnavnet eller modelnummeret, kun hvis det står som tekst på billedet. Ellers tom tekst.",
                    schema: text
                ),
                .init(
                    name: "category",
                    description: "Den kategori, genstandstypen hører til. \"\(noCategory)\" hvis ingen passer.",
                    schema: choice("Kategori", categoryNames + [noCategory])
                ),
                .init(
                    name: "serialNumber",
                    description: "Serienummeret præcis som det står i teksten, uden \"S/N\" eller \"Serial\". Ellers tom tekst.",
                    schema: text
                ),
            ]
        )
        return try GenerationSchema(root: root, dependencies: [])
    }

    // MARK: - Text recognition

    private static func recognizeText(in image: CGImage) async throws -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Serial numbers aren't words, so don't "correct" them.
        request.usesLanguageCorrection = false
        request.recognitionLanguages = [Locale.Language(identifier: "da"), Locale.Language(identifier: "en")]
        let observations = try await request.perform(on: image)
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }

    // MARK: - Helpers

    /// Cleans up the model the model returned: drops a leading "Model" label and
    /// the brand, and rejects it if it is really the serial number.
    private static func modelName(_ value: String, brand: String?, serialNumber: String?) -> String? {
        guard var model = nonEmpty(value) else { return nil }
        model = model.replacing(/(?i)^(?:model(?:nr\.?|nummer)?|type)\s*[:.]?\s*/, with: "")
        if let brand {
            model = model.replacingOccurrences(of: brand, with: "", options: .caseInsensitive)
        }
        model = model.trimmingCharacters(in: .whitespaces)
        guard !model.isEmpty else { return nil }

        if let serialNumber {
            let normalize = { (text: String) in text.uppercased().filter { $0.isLetter || $0.isNumber } }
            if normalize(serialNumber).contains(normalize(model)) { return nil }
        }
        return model
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func capitalizedFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}

nonisolated extension EquipmentAutofill.Answer {
    init(_ content: GeneratedContent) throws {
        self.init(
            subject: try content.value(forProperty: "subject"),
            itemType: try content.value(forProperty: "itemType"),
            brand: try content.value(forProperty: "brand"),
            model: try content.value(forProperty: "model"),
            category: try content.value(forProperty: "category"),
            serialNumber: try content.value(forProperty: "serialNumber")
        )
    }
}
