import SwiftData
import SwiftUI

@main
struct ElyraBudgetApp: App {
    @State private var proAccess = ProAccessManager()

    private let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserSettings.self,
            BudgetGroup.self,
            Budget.self,
            Transaction.self,
            FixedCost.self,
            SavingsGoal.self,
            SavingsContribution.self
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
                .dismissKeyboardOnTap()
                .environment(proAccess)
        }
        .modelContainer(sharedModelContainer)
    }
}
