import SwiftData
import SwiftUI
import UserNotifications

@main
struct ElyraBudgetApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(CloudKitShareAppDelegate.self)
    private var cloudKitShareAppDelegate
    #endif

    @State private var proAccess = ProAccessManager()
    @State private var appLockManager = AppLockManager()
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
        let useCloudKit = AppRuntimeConfiguration.isCloudKitEnabled(
            environment: processInfo.environment,
            arguments: processInfo.arguments
        )

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

    init() {
        let openAction = UNNotificationAction(
            identifier: "open",
            title: "Öffnen",
            options: [.foreground]
        )
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(
                identifier: "fixed-costs",
                actions: [openAction],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "budget",
                actions: [openAction],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "savings",
                actions: [openAction],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "summary",
                actions: [openAction],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "transactions",
                actions: [openAction],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "bookings",
                actions: [openAction],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "sync",
                actions: [openAction],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: "feedback",
                actions: [openAction],
                intentIdentifiers: [],
                options: []
            )
        ])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .dismissKeyboardOnTap()
                .environment(proAccess)
                .environment(appLockManager)
                .environment(cloudKitSyncMonitor)
        }
        .modelContainer(sharedModelContainer)
    }
}
