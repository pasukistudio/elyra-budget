import SwiftData
import SwiftUI

@main
struct ElyraBudgetApp: App {
    @State private var proAccess = ProAccessManager()
    @State private var cloudKitSyncMonitor = CloudKitSyncMonitor()

    private let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserSettings.self,
            BudgetGroup.self,
            BudgetGroupMonthlyAllocation.self,
            Budget.self,
            Transaction.self,
            FixedCost.self,
            SavingsGoal.self,
            SavingsContribution.self
        ])

        let processInfo = ProcessInfo.processInfo
        let isRunningUnderXCTest = processInfo.arguments.contains("-XCTest")
            || processInfo.environment["XCTestConfigurationFilePath"] != nil
            || processInfo.environment["XCTestSessionIdentifier"] != nil
        let useCloudKit = !isRunningUnderXCTest
            && processInfo.environment["ELYRA_BUDGET_USE_CLOUDKIT"] != "NO"

        let configuration: ModelConfiguration
        if useCloudKit {
            configuration = ModelConfiguration(
                "ElyraBudget",
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private(
                    "iCloud.de.pascal.ElyraBudgetNew"
                )
            )
        } else {
            configuration = ModelConfiguration(
                "ElyraBudgetTests",
                schema: schema,
                isStoredInMemoryOnly: true
            )
        }

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
                .environment(cloudKitSyncMonitor)
        }
        .modelContainer(sharedModelContainer)
    }
}
