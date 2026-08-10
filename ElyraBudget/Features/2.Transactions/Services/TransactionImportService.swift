import Foundation

struct CSVImportRow: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let title: String
    let type: TransactionType
    let amount: Decimal
    let budgetName: String?
    let groupName: String?
    let note: String
}

enum TransactionImportError: LocalizedError {
    case unreadableFile
    case missingHeader
    case invalidRows(Int)

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "Die CSV-Datei konnte nicht gelesen werden."
        case .missingHeader:
            return "Die Datei enthält keine gültige Kopfzeile."
        case .invalidRows(let count):
            return "\(count) Zeilen konnten nicht erkannt werden. Bitte prüfe Datum, Titel und Betrag."
        }
    }
}

enum TransactionImportService {
    nonisolated static func parse(data: Data) throws -> [CSVImportRow] {
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .windowsCP1252) else {
            throw TransactionImportError.unreadableFile
        }

        let lines = parseCSV(text)
        guard let header = lines.first else { throw TransactionImportError.missingHeader }
        let normalizedHeader = header.map(normalize)
        guard let dateIndex = normalizedHeader.firstIndex(of: "datum"),
              let titleIndex = normalizedHeader.firstIndex(of: "titel"),
              let amountIndex = normalizedHeader.firstIndex(of: "betrag") else {
            throw TransactionImportError.missingHeader
        }

        let typeIndex = normalizedHeader.firstIndex(of: "typ")
        let budgetIndex = normalizedHeader.firstIndex(of: "budget")
        let groupIndex = normalizedHeader.firstIndex(of: "bereich")
        let noteIndex = normalizedHeader.firstIndex(of: "notiz")
        var rows: [CSVImportRow] = []
        var invalidRowCount = 0

        for values in lines.dropFirst() where !values.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            guard let date = date(at: dateIndex, values: values),
                  let title = value(at: titleIndex, values: values), !title.isEmpty,
                  let amount = amount(at: amountIndex, values: values) else {
                invalidRowCount += 1
                continue
            }

            rows.append(CSVImportRow(
                date: date,
                title: title,
                type: transactionType(at: typeIndex, values: values),
                amount: amount,
                budgetName: optionalValue(at: budgetIndex, values: values),
                groupName: optionalValue(at: groupIndex, values: values),
                note: optionalValue(at: noteIndex, values: values) ?? ""
            ))
        }

        guard !rows.isEmpty else {
            throw invalidRowCount > 0 ? TransactionImportError.invalidRows(invalidRowCount) : TransactionImportError.missingHeader
        }
        return rows
    }

    private nonisolated static func parseCSV(_ text: String) -> [[String]] {
        let separator: Character = text.firstIndex(of: ";") != nil ? ";" : ","
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var characters = Array(text)
        characters.append("\n")

        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    quoted.toggle()
                }
            } else if character == separator && !quoted {
                row.append(field)
                field = ""
            } else if character == "\n" && !quoted {
                row.append(field.trimmingCharacters(in: .newlines))
                rows.append(row)
                row = []
                field = ""
            } else if character != "\r" {
                field.append(character)
            }
            index += 1
        }
        return rows
    }

    private nonisolated static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
    }

    private nonisolated static func value(at index: Int, values: [String]) -> String? {
        guard values.indices.contains(index) else { return nil }
        return values[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func optionalValue(at index: Int?, values: [String]) -> String? {
        guard let index, let value = value(at: index, values: values), !value.isEmpty else { return nil }
        return value
    }

    private nonisolated static func date(at index: Int, values: [String]) -> Date? {
        guard let value = value(at: index, values: values) else { return nil }
        let formats = ["yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd", "dd.MM.yyyy", "dd/MM/yyyy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = .current
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private nonisolated static func amount(at index: Int, values: [String]) -> Decimal? {
        guard let value = value(at: index, values: values) else { return nil }
        let trimmed = value
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: " ", with: "")
        let cleaned: String
        if trimmed.contains(",") {
            cleaned = trimmed
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
        } else {
            cleaned = trimmed
        }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    private nonisolated static func transactionType(at index: Int?, values: [String]) -> TransactionType {
        guard let index, let raw = value(at: index, values: values)?.lowercased() else { return .expense }
        if raw.contains("income") || raw.contains("einnah") { return .income }
        if raw.contains("refund") || raw.contains("erstatt") { return .refund }
        return .expense
    }
}
