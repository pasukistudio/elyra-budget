import Foundation

enum TransactionReceiptService {
    nonisolated private static let directoryName = "TransactionReceipts"

    static func importFile(from url: URL) throws -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let directory = try receiptDirectory()
        let filename = "\(UUID().uuidString)-\(url.lastPathComponent)"
        try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(filename))
        return filename
    }

    nonisolated static func url(for filename: String) -> URL? {
        try? receiptDirectory().appendingPathComponent(filename)
    }

    nonisolated static func data(for filename: String) -> Data? {
        guard let url = url(for: filename) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func temporaryURL(for filename: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ElyraBudgetReceipts", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    nonisolated private static func receiptDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
