import Foundation

enum TransactionReceiptService {
    private static let directoryName = "TransactionReceipts"

    static func importFile(from url: URL) throws -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let directory = try receiptDirectory()
        let filename = "\(UUID().uuidString)-\(url.lastPathComponent)"
        try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(filename))
        return filename
    }

    static func url(for filename: String) -> URL? {
        try? receiptDirectory().appendingPathComponent(filename)
    }

    private static func receiptDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
