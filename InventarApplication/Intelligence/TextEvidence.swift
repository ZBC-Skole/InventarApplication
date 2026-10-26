//
//  TextEvidence.swift
//  InventarApplication
//

import Foundation

/// The text Vision found in a photo, used to check the model's answers.
///
/// Brand, model and serial number are only accepted when they can be found
/// here, so nothing is filled in that isn't actually written on the item.
nonisolated struct TextEvidence: Sendable {
    let lines: [String]
    private let normalizedLines: [String]

    init(lines: [String]) {
        self.lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        normalizedLines = self.lines.map(Self.normalize)
    }

    var isEmpty: Bool { lines.isEmpty }

    /// The text as given to the model.
    var promptDescription: String {
        isEmpty
            ? "Der er ingen læsbar tekst på billedet."
            : "Tekst, der kan læses på billedet:\n" + lines.joined(separator: "\n")
    }

    /// Whether every word of `value` appears in the text, ignoring case,
    /// spaces and punctuation. Used for brand and model names.
    func contains(_ value: String) -> Bool {
        let words = value
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { Self.normalize(String($0)) }
            .filter { $0.count >= 2 }
        return !words.isEmpty && words.allSatisfy { word in
            normalizedLines.contains { $0.contains(word) }
        }
    }

    /// Whether `value` appears as one piece on a single line. Used for serial numbers.
    func containsVerbatim(_ value: String) -> Bool {
        let needle = Self.normalize(value)
        return !needle.isEmpty && normalizedLines.contains { $0.contains(needle) }
    }

    /// Lines with text other than `values` and common labels, in reading order.
    func lines(notCoveredBy values: [String]) -> [String] {
        let usedWords = Set(values.flatMap(Self.words))
        return lines.filter { line in
            let words = Self.words(in: line).filter { !Self.labelWords.contains($0) }
            return !words.isEmpty && !words.allSatisfy(usedWords.contains)
        }
    }

    /// Whether `value` is only label words like "Model" or "Serial No.", which
    /// the model sometimes returns as a brand.
    static func isOnlyLabelWords(_ value: String) -> Bool {
        let words = words(in: value)
        return words.isEmpty || words.allSatisfy { labelWords.contains($0) || otherIdentifierWords.contains($0) }
    }

    /// A serial number written next to a label such as "S/N", "Serial No." or
    /// "Serienummer". Read straight from the text, without the model.
    func labeledSerialNumber() -> String? {
        for line in lines {
            if let match = line.firstMatch(of: Self.serialNumberPattern) {
                let value = String(match.output.1).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                if Self.looksLikeSerialNumber(value) { return value }
            }
        }
        return nil
    }

    /// Whether `value` is written next to a label for another kind of number,
    /// such as "Model", "P/N" or "IMEI", so it shouldn't be taken as the serial number.
    func isLabeledAsOtherIdentifier(_ value: String) -> Bool {
        let needle = Self.normalize(value)
        return lines.indices.contains { index in
            normalizedLines[index].contains(needle)
                && lines[index].contains(Self.otherIdentifierPattern)
        }
    }

    /// Serial numbers are at least four characters and contain a digit;
    /// this rules out ordinary words picked from the text.
    static func looksLikeSerialNumber(_ value: String) -> Bool {
        value.count >= 4 && value.contains(where: \.isNumber)
    }

    // MARK: - Helpers

    nonisolated(unsafe) private static let serialNumberPattern =
        /(?i)(?:\bS\s?\/\s?N\b|\bSN\b|\bSerial(?:\s*(?:No\.?|Number|Nr\.?|#))?|\bSerie(?:nummer|nr\.?))\s*[:#.]?\s*([A-Z0-9][A-Z0-9\-]{3,})/

    nonisolated(unsafe) private static let otherIdentifierPattern =
        /(?i)\b(?:Model(?:nr\.?|nummer)?|Part|P\s?\/\s?N|EMC|IMEI|FCC(?:\s?ID)?|EAN|UPC|SKU|Varenr\.?)\b/

    /// Label words that say nothing on their own, e.g. the "S/N" in "S/N C02…".
    private static let labelWords: Set<String> = [
        "S", "N", "SN", "SERIAL", "NO", "NUMBER", "NR", "SERIENUMMER", "MODEL", "MODELNR", "TYPE",
    ]

    private static let otherIdentifierWords: Set<String> = [
        "PART", "PN", "P", "EMC", "IMEI", "FCC", "ID", "EAN", "UPC", "SKU", "VARENR", "MADE", "IN",
    ]

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { normalize(String($0)) }
    }

    private static func normalize(_ text: String) -> String {
        text.uppercased().filter { $0.isLetter || $0.isNumber }
    }
}
