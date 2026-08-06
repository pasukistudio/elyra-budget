import OSLog

enum AppLogger {
    static let persistence = Logger(
        subsystem: "de.pascal.ElyraBudget",
        category: "Persistence"
    )
}
