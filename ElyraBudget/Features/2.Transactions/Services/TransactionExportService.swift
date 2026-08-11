import Foundation
import CoreGraphics
import CoreText

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum TransactionExportFormat {
    case csv
    case pdf

    var fileExtension: String {
        switch self {
        case .csv: "csv"
        case .pdf: "pdf"
        }
    }
}

enum TransactionExportService {
    static func write(
        transactions: [Transaction],
        month: Date,
        currencyCode: String,
        format: TransactionExportFormat
    ) throws -> URL {
        let calendar = Calendar.autoupdatingCurrent
        let monthTitle = month.formatted(.dateTime.month(.wide).year())
        let year = calendar.component(.year, from: month)
        let monthNumber = calendar.component(.month, from: month)
        let fileName = String(format: "Elyra-Budget-%04d-%02d", year, monthNumber)
        let fileManager = FileManager.default
        let exportDirectory = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("ElyraBudgetExports", isDirectory: true)
        try fileManager.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true
        )

        let url = exportDirectory.appendingPathComponent(
            "\(fileName).\(format.fileExtension)",
            isDirectory: false
        )

        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        switch format {
        case .csv:
            let content = csv(
                transactions: transactions,
                calendar: calendar,
                currencyCode: currencyCode
            )
            guard let data = content.data(using: .utf8) else {
                throw ExportError.csvEncodingFailed
            }
            try data.write(to: url, options: .atomic)
        case .pdf:
            let data = pdf(
                transactions: transactions,
                monthTitle: monthTitle,
                currencyCode: currencyCode
            )
            try data.write(to: url, options: .atomic)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw ExportError.fileWriteFailed
        }

        return url
    }

    private static func csv(
        transactions: [Transaction],
        calendar: Calendar,
        currencyCode: String
    ) -> String {
        var rows = ["Datum;Titel;Typ;Betrag;Währung;Budget;Bereich;Notiz"]
        rows += transactions
            .sorted { $0.date < $1.date }
            .map { transaction in
                [
                    transaction.date.formatted(.dateTime.day().month().year()),
                    transaction.title,
                    transaction.type.title,
                    NSDecimalNumber(decimal: transaction.amount).stringValue,
                    currencyCode,
                    transaction.budget?.name ?? "",
                    transaction.effectiveGroup?.name ?? "",
                    transaction.note
                ]
                .map(escapeCSV)
                .joined(separator: ";")
            }
        return rows.joined(separator: "\n") + "\n"
    }

    private static func pdf(
        transactions: [Transaction],
        monthTitle: String,
        currencyCode: String
    ) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            return Data()
        }

        context.beginPDFPage([kCGPDFContextMediaBox as String: pageRect] as CFDictionary)
        defer {
            context.endPDFPage()
            context.closePDF()
        }

        var y: CGFloat = 800

        func draw(_ text: String, bold: Bool = false, size: CGFloat = 10) {
            context.textPosition = CGPoint(x: 40, y: y)
            let fontName = bold ? "Helvetica-Bold" : "Helvetica"
            let font = CTFontCreateWithName(fontName as CFString, size, nil)
            let attributedText = NSAttributedString(
                string: text,
                attributes: [.font: font]
            )
            CTLineDraw(CTLineCreateWithAttributedString(attributedText), context)
            y -= size + 10
        }

        func beginNextPage() {
            context.endPDFPage()
            context.beginPDFPage([kCGPDFContextMediaBox as String: pageRect] as CFDictionary)
            y = 800
        }

        draw("Elyra Budget – Buchungen", bold: true, size: 20)
        draw(monthTitle, size: 10)

        let expenses = transactions
            .filter { $0.type == .expense }
            .reduce(Decimal.zero) { $0 + abs($1.amount) }
        let income = transactions
            .filter { $0.type == .income }
            .reduce(Decimal.zero) { $0 + abs($1.amount) }
        draw("Einnahmen: \(income) \(currencyCode)    Ausgaben: \(expenses) \(currencyCode)", bold: true)

        for transaction in transactions.sorted(by: { $0.date < $1.date }) {
            if y < 42 {
                beginNextPage()
            }
            let line = "\(transaction.date.formatted(.dateTime.day().month().year()))   \(transaction.title)   \(transaction.type.title)   \(transaction.amount) \(currencyCode)"
            draw(line)
        }

        return data as Data
    }

    private nonisolated static func escapeCSV(_ value: String) -> String {
        guard value.contains(";") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

enum ExportError: LocalizedError {
    case pdfUnavailable
    case csvEncodingFailed
    case fileWriteFailed

    var errorDescription: String? {
        switch self {
        case .pdfUnavailable: "PDF-Export ist auf dieser Plattform nicht verfügbar."
        case .csvEncodingFailed: "Der CSV-Export konnte nicht kodiert werden."
        case .fileWriteFailed: "Die Exportdatei konnte nicht erstellt werden."
        }
    }
}
