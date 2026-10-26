//
//  EquipmentAutofill.swift
//  InventarApplication
//

import CoreGraphics
import Foundation
import FoundationModels
import ImageIO
import Vision

/// Form values suggested from a photo. `nil` means there was no confident answer.
nonisolated struct EquipmentSuggestion: Sendable, Equatable {
    var name: String?
    var categoryName: String?
    var serialNumber: String?
    var notes: String?

    var isEmpty: Bool {
        name == nil && categoryName == nil && serialNumber == nil && notes == nil
    }
}

/// Suggests form values for a photo of equipment, entirely on device.
///
/// Vision reads any text in the photo (e.g. a serial number sticker), and the
/// Apple Intelligence foundation model looks at the image together with that
/// text to name the item, pick a category and describe it.
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

    /// Category value the model picks when nothing on the list fits.
    private static let noCategory = "Ingen"

    @concurrent
    static func suggest(
        from imageData: Data,
        categoryNames: [String]
    ) async throws -> EquipmentSuggestion {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Failure.unreadableImage }

        let recognizedLines = (try? await recognizeText(in: image)) ?? []
        let recognizedText =
            recognizedLines.isEmpty
            ? "Der blev ikke fundet nogen tekst på billedet."
            : "Tekst fundet på billedet:\n" + recognizedLines.joined(separator: "\n")

        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            schema: try schema(categoryNames: categoryNames)
        ) {
            "Udfyld oplysningerne for udstyret på billedet."
            "Mulige kategorier: \(categoryNames.joined(separator: ", "))."
            recognizedText
            Attachment(image)
        }

        let content = response.content
        let category = try content.value(String.self, forProperty: "category")
        return EquipmentSuggestion(
            name: nonEmpty(try content.value(String.self, forProperty: "name")),
            categoryName: categoryNames.contains(category) ? category : nil,
            serialNumber: verifiedSerialNumber(
                try content.value(String.self, forProperty: "serialNumber"),
                in: recognizedLines
            ),
            notes: nonEmpty(try content.value(String.self, forProperty: "notes"))
        )
    }

    // MARK: - Prompt

    private static let instructions = """
        Du hjælper med at registrere udstyr i et inventarsystem ud fra et foto.
        Beskriv kun det, du faktisk kan se på billedet. Gæt ikke.
        Navnet skal være mærke og model, hvis de kan ses, ellers en kort, \
        almindelig betegnelse for genstanden.
        Skriv altid noter på dansk.
        """

    private static func schema(categoryNames: [String]) throws -> GenerationSchema {
        let text = DynamicGenerationSchema(type: String.self)
        let category = DynamicGenerationSchema(
            name: "Kategori",
            anyOf: categoryNames + [noCategory]
        )

        let root = DynamicGenerationSchema(
            name: "Udstyr",
            properties: [
                .init(
                    name: "name",
                    description: "Kort navn med mærke og model, f.eks. \"MacBook Pro 14\" eller \"Sony A7 IV\". Højst fem ord.",
                    schema: text
                ),
                .init(
                    name: "category",
                    description: "Den kategori, der passer bedst. \"\(noCategory)\" hvis ingen passer.",
                    schema: category
                ),
                .init(
                    name: "serialNumber",
                    description: "Serienummeret præcis som det står i den fundne tekst, uden \"S/N\" eller \"Serial\". Tom tekst hvis der ikke står et serienummer.",
                    schema: text
                ),
                .init(
                    name: "notes",
                    description: "En til to korte sætninger på dansk om genstandens udseende: farve, kendetegn og synlig stand.",
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
        request.usesLanguageCorrection = false
        let observations = try await request.perform(on: image)
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }

    // MARK: - Validation

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Only accepts a serial number that actually appears in the recognized
    /// text, so the model can't invent one.
    private static func verifiedSerialNumber(_ value: String, in lines: [String]) -> String? {
        guard let serialNumber = nonEmpty(value), serialNumber.count >= 4 else { return nil }
        let normalize = { (text: String) in
            text.uppercased().filter { $0.isLetter || $0.isNumber }
        }
        let needle = normalize(serialNumber)
        guard !needle.isEmpty,
            lines.contains(where: { normalize($0).contains(needle) })
        else { return nil }
        return serialNumber
    }
}
