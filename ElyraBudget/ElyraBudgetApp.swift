import SwiftUI
import SwiftData

@main
struct ElyraBudgetApp: App {
    @State private var proAccess = ProAccessManager()

    private let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserSettings.self,
            Budget.self
        ])

        let configuration = ModelConfiguration(
            "ElyraBudget",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(
                "iCloud.de.pascal.ElyraBudgetNew"
            )
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            fatalError(
                "ModelContainer konnte nicht erstellt werden: \(error)"
            )
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(proAccess)
        }
        .modelContainer(sharedModelContainer)
    }
}
