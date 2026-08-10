import Foundation

#if os(iOS)
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
        let fileName = "Elyra-Budget-\(month.formatted(.dateTime.year().month(.twoDigits)))"
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let url = temporaryDirectory.appendingPathComponent("\(fileName).\(format.fileExtension)")

        switch format {
        case .csv:
            let content = csv(
                transactions: transactions,
                calendar: calendar,
                currencyCode: currencyCode
            )
            try content.data(using: .utf8)?.write(to: url, options: .atomic)
        case .pdf:
            #if os(iOS)
            let data = pdf(
                transactions: transactions,
                monthTitle: monthTitle,
                currencyCode: currencyCode
            )
            try data.write(to: url, options: .atomic)
            #else
            throw ExportError.pdfUnavailable
            #endif
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

    #if os(iOS)
    private static func pdf(
        transactions: [Transaction],
        monthTitle: String,
        currencyCode: String
    ) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 20)
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10)
        ]
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10)
        ]

        return renderer.pdfData { context in
            var y: CGFloat = 42
            context.beginPage()
            "Elyra Budget – Buchungen".draw(at: CGPoint(x: 40, y: y), withAttributes: titleAttributes)
            y += 30
            monthTitle.draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttributes)
            y += 28

            let expenses = transactions
                .filter { $0.type == .expense }
                .reduce(Decimal.zero) { $0 + abs($1.amount) }
            let income = transactions
                .filter { $0.type == .income }
                .reduce(Decimal.zero) { $0 + abs($1.amount) }
            "Einnahmen: \(income) \(currencyCode)    Ausgaben: \(expenses) \(currencyCode)"
                .draw(at: CGPoint(x: 40, y: y), withAttributes: headerAttributes)
            y += 30

            for transaction in transactions.sorted(by: { $0.date < $1.date }) {
                if y > 800 {
                    context.beginPage()
                    y = 42
                }
                let line = "\(transaction.date.formatted(.dateTime.day().month().year()))   \(transaction.title)   \(transaction.type.title)   \(transaction.amount) \(currencyCode)"
                line.draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttributes)
                y += 18
            }
        }
    }
    #endif

    private nonisolated static func escapeCSV(_ value: String) -> String {
        guard value.contains(";") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

enum ExportError: LocalizedError {
    case pdfUnavailable

    var errorDescription: String? {
        switch self {
        case .pdfUnavailable: "PDF-Export ist auf dieser Plattform nicht verfügbar."
        }
    }
}
