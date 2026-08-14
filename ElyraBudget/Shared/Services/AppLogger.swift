import OSLog

enum AppLogger {
    static let persistence = Logger(
        subsystem: "de.pasukistudio.elyrabudget",
        category: "Persistence"
    )
}
