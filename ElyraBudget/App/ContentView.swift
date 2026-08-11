import SwiftData
import StoreKit
import SwiftUI
import os


struct ContentView: View {

    /// Preview-only switch that renders the onboarding inline in Canvas.
    /// Production callers keep the default value and use the normal startup flow.
    private let showsOnboardingPreview: Bool

    init(showsOnboardingPreview: Bool = false) {
        self.showsOnboardingPreview = showsOnboardingPreview
    }

    // MARK: - SwiftData

    @Environment(\.modelContext)
    private var modelContext

    @Query private var userSettings: [UserSettings]
    @Query(
        filter: #Predicate<BudgetGroup> { !$0.isArchived },
        sort: [
            SortDescriptor<BudgetGroup>(\.sortOrder),
            SortDescriptor<BudgetGroup>(\.createdAt)
        ]
    )
    private var budgetGroups: [BudgetGroup]
    @Query(sort: [SortDescriptor<Budget>(\.sortOrder)])
    private var budgets: [Budget]
    @Query(sort: [SortDescriptor<FixedCost>(\.createdAt)])
    private var fixedCosts: [FixedCost]
    @Query(sort: [SortDescriptor<SavingsGoal>(\.createdAt)])
    private var savingsGoals: [SavingsGoal]
    @Query(sort: [SortDescriptor<Transaction>(\.date)])
    private var transactions: [Transaction]
    @Query(sort: [SortDescriptor<SavingsContribution>(\.date)])
    private var savingsContributions: [SavingsContribution]

    private var appCurrencyCode: String {
        userSettings.first?.currencyRawValue ?? AppCurrency.eur.rawValue
    }

    // MARK: - Environment

    @Environment(\.colorScheme)
    private var systemColorScheme
    @Environment(\.scenePhase)
    private var scenePhase
    @Environment(\.requestReview)
    private var requestReview

    // MARK: - Navigation & Sheets

    @State private var selectedSection: AppSection = .overview
    @State private var selectedDate = Date()

    @State private var showingMonthPicker = false
    @State private var showingBudgetEditor = false
    @State private var showingBudgetManagement = false
    @State private var showingArchivedBudgets = false
    @State private var showingTransactionEditor = false
    @State private var requestedTransactionToolbarAction: TransactionToolbarAction?
    @State private var requestingFixedCostEditor = false
    @State private var requestingSavingsGoalEditor = false
    @State private var requestingSavingsReserveEditor = false
    @State private var showingSavingsManagement = false
    @State private var showingArchivedSavings = false
    @State private var selectedBudgetGroup: BudgetGroup?
    @AppStorage("elyraBudget.selectedBudgetGroupID")
    private var persistedSelectedBudgetGroupID = ""
    @State private var showingBudgetGroupManagement = false
    @State private var showingSettings = false
    @State private var showingOnboarding = false
    @AppStorage("elyraBudgetAppLaunchCount")
    private var appLaunchCount = 0
    @State private var hasCountedCurrentLaunch = false
    @Environment(CloudKitSyncMonitor.self)
    private var cloudKitSyncMonitor
    @Environment(ProAccessManager.self)
    private var proAccess
    @Environment(AppLockManager.self)
    private var appLockManager

    // MARK: - Hauptansicht

    var body: some View {
        Group {
            if showsOnboardingPreview {
                OnboardingView(group: nil)
            } else {
                #if os(macOS)
                if proAccess.requiresMacPro {
                    MacProRequiredView()
                } else {
                    macLayout
                }
                #else
                iOSLayout
                #endif
            }
        }
        .overlay {
            if appLockManager.isLocked {
                AppLockView()
            }
        }
        .environment(\.appCurrencyCode, appCurrencyCode)
        .sheet(isPresented: $showingBudgetGroupManagement, onDismiss: {
            if selectedBudgetGroup?.isArchived == true {
                selectedBudgetGroup = nil
            }
        }) {
            BudgetGroupManagementView()
        }
        .task {
            await proAccess.refreshEntitlement()
            appLockManager.lockIfNeeded(
                isEnabled: userSettings.first?.appLockEnabled ?? false,
                hasPro: proAccess.hasPro
            )
            await importPendingCloudKitShareIfNeeded()
            await ensureDefaultBudgetGroupAfterCloudKitSync()
            await pullSharedAreasIfNeeded()
            restoreSelectedBudgetGroup()
            migrateLocalReceiptsToSyncableData()
            writeWidgetSnapshot()
            presentOnboardingIfNeeded()
            registerAppLaunchIfNeeded()
            applyQuieterNotificationDefaultsIfNeeded()
            processAutomaticSavingsGoals()
            processAutomaticFixedCosts()
            processRoundUps()
            rescheduleAppNotifications()
        }
        .task {
            await proAccess.listenForTransactionUpdates()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                appLockManager.lockIfNeeded(
                    isEnabled: userSettings.first?.appLockEnabled ?? false,
                    hasPro: proAccess.hasPro
                )
            }
            guard newPhase == .active else { return }
            registerAppLaunchIfNeeded()
            Task {
                await proAccess.refreshEntitlement()
                await importPendingCloudKitShareIfNeeded()
                await pullSharedAreasIfNeeded()
                migrateLocalReceiptsToSyncableData()
                writeWidgetSnapshot()
            }
            processAutomaticSavingsGoals()
            processAutomaticFixedCosts()
            processRoundUps()
            rescheduleAppNotifications()
        }
        .onChange(of: selectedBudgetGroup?.id) { _, newID in
            persistedSelectedBudgetGroupID = newID?.uuidString ?? ""
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            guard oldPhase != .background, newPhase == .background else { return }
            Task {
                await uploadSharedAreasIfNeeded()
            }
        }
        .onChange(of: cloudKitSyncMonitor.status) { _, status in
            switch status {
            case .failed:
                UserDefaults.standard.set(true, forKey: "elyraBudget.syncFailureActive")
                guard userSettings.first?.syncErrorNotificationsEnabled ?? true else { return }
                Task {
                    await AppNotificationScheduler.scheduleSyncError(
                        message: cloudKitSyncMonitor.errorMessage ?? "Bitte prüfe deine iCloud-Verbindung.",
                        enabled: true
                    )
                }
            case .succeeded where UserDefaults.standard.bool(forKey: "elyraBudget.syncFailureActive"):
                UserDefaults.standard.set(false, forKey: "elyraBudget.syncFailureActive")
                Task {
                    await AppNotificationScheduler.scheduleSyncRecovery(
                        enabled: userSettings.first?.syncRecoveryNotificationsEnabled ?? true
                    )
                }
            default:
                break
            }
        }
    }

    @MainActor
    private func importPendingCloudKitShareIfNeeded() async {
        guard cloudKitSyncMonitor.isCloudKitEnabled else { return }
        do {
            _ = try await CloudKitSharedAreaService.shared.importPendingShare(modelContext: modelContext)
        } catch {
            AppLogger.persistence.error("Geteilter CloudKit-Bereich konnte nicht importiert werden: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func pullSharedAreasIfNeeded() async {
        guard cloudKitSyncMonitor.isCloudKitEnabled else { return }
        for group in budgetGroups {
            do {
                try await CloudKitSharedAreaService.shared.pullSharedArea(
                    group: group,
                    modelContext: modelContext
                )
            } catch {
                AppLogger.persistence.error("Geteilter Bereich konnte nicht aktualisiert werden: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func uploadSharedAreasIfNeeded() async {
        guard cloudKitSyncMonitor.isCloudKitEnabled else { return }
        for group in budgetGroups {
            do {
                try await CloudKitSharedAreaService.shared.updateSharedArea(group: group)
            } catch {
                AppLogger.persistence.error("Geteilter Bereich konnte nicht gespeichert werden: \(error.localizedDescription)")
            }
        }
    }

    private func writeWidgetSnapshot() {
        guard proAccess.hasPro else {
            WidgetSnapshotWriter.clear()
            return
        }
        WidgetSnapshotWriter.write(
            groups: budgetGroups,
            currencyCode: appCurrencyCode,
            month: selectedDate
        )
    }

    private func processAutomaticFixedCosts() {
        do {
            try FixedCostScheduler.processAutomaticBookings(
                fixedCosts: fixedCosts,
                savingsGoals: savingsGoals,
                transactions: transactions,
                modelContext: modelContext
            )
        } catch {
            AppLogger.persistence.error(
                "Automatische Fixkosten konnten nicht gebucht werden: \(error)"
            )
            Task {
                await AppNotificationScheduler.scheduleAutomaticBookingFailure(
                    message: "Eine automatische Fixkostenbuchung konnte nicht erstellt werden.",
                    enabled: userSettings.first?.automaticBookingFailureNotificationsEnabled ?? true
                )
            }
        }
    }

    private func processRoundUps() {
        do {
            let allTransactions = try modelContext.fetch(FetchDescriptor<Transaction>())
            let allContributions = try modelContext.fetch(FetchDescriptor<SavingsContribution>())
            try TransactionRoundUpService.applyAllIfNeeded(
                transactions: allTransactions,
                groups: budgetGroups,
                savingsGoals: savingsGoals,
                contributions: allContributions,
                modelContext: modelContext
            )
        } catch {
            AppLogger.persistence.error("Buchungen konnten nicht aufgerundet werden: \(error)")
        }
    }

    private func migrateLocalReceiptsToSyncableData() {
        var changed = false
        for transaction in transactions where transaction.receiptData == nil {
            guard let filename = transaction.receiptFilename,
                  let data = TransactionReceiptService.data(for: filename) else { continue }
            transaction.receiptData = data
            transaction.updatedAt = .now
            changed = true
        }
        guard changed else { return }
        do {
            try modelContext.save()
        } catch {
            AppLogger.persistence.error("Belegdaten konnten nicht synchronisiert werden: \(error)")
        }
    }

    private func applyQuieterNotificationDefaultsIfNeeded() {
        let key = "elyraBudget.notificationDefaults.v2Applied"
        guard !UserDefaults.standard.bool(forKey: key),
              let settings = userSettings.first else {
            return
        }

        // Keep important warnings active, while disabling noisy optional alerts.
        settings.savingsContributionNotificationsEnabled = false
        settings.monthlySummaryNotificationsEnabled = false
        settings.forecastRiskNotificationsEnabled = false
        settings.syncRecoveryNotificationsEnabled = false
        settings.feedbackStatusNotificationsEnabled = false
        settings.unusualExpenseNotificationsEnabled = false
        settings.updatedAt = .now

        do {
            try modelContext.save()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            AppLogger.persistence.error(
                "Benachrichtigungseinstellungen konnten nicht angepasst werden: \(error)"
            )
        }
    }

    private func processAutomaticSavingsGoals() {
        do {
            try SavingsGoalScheduler.processAutomaticBookings(
                goals: savingsGoals,
                transactions: transactions,
                modelContext: modelContext
            )
        } catch {
            AppLogger.persistence.error(
                "Automatische Sparbuchungen konnten nicht gebucht werden: \(error)"
            )
            Task {
                await AppNotificationScheduler.scheduleAutomaticBookingFailure(
                    message: "Eine automatische Sparbuchung konnte nicht erstellt werden.",
                    enabled: userSettings.first?.automaticBookingFailureNotificationsEnabled ?? true
                )
            }
        }
    }

    private func rescheduleAppNotifications() {
        Task {
            var currentBudgets = budgets
            var currentTransactions = transactions
            do {
                currentBudgets = try modelContext.fetch(
                    FetchDescriptor<Budget>(sortBy: [SortDescriptor(\.sortOrder)])
                )
                currentTransactions = try modelContext.fetch(
                    FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date)])
                )
            } catch {
                AppLogger.persistence.error(
                    "Aktuelle Daten für Benachrichtigungen konnten nicht geladen werden: \(error)"
                )
            }
            await AppNotificationScheduler.reschedule(
                fixedCosts: fixedCosts,
                savingsGoals: savingsGoals,
                budgets: currentBudgets,
                transactions: currentTransactions,
                settings: userSettings.first
            )
        }
    }

    private func ensureDefaultBudgetGroupAfterCloudKitSync() async {
        // SwiftData imports CloudKit records asynchronously. Give an existing
        // budget group time to arrive before creating the default one.
        for _ in 0..<6 {
            guard !Task.isCancelled else { return }

            let existingGroups: [BudgetGroup]
            do {
                existingGroups = try modelContext.fetch(FetchDescriptor<BudgetGroup>())
            } catch {
                AppLogger.persistence.error(
                    "Budgetbereiche konnten nach der CloudKit-Synchronisierung nicht geladen werden: \(error)"
                )
                return
            }

            if !existingGroups.isEmpty {
                ensureDefaultBudgetGroup()
                return
            }

            try? await Task.sleep(for: .milliseconds(500))
        }

        ensureDefaultBudgetGroup()
    }

    private func ensureDefaultBudgetGroup() {
        do {
            _ = try BudgetGroupMigration.ensureDefaultGroupAndMigrate(in: modelContext)
        } catch {
            AppLogger.persistence.error(
                "Standard-Budgetbereich konnte nicht erstellt werden: \(error)"
            )
        }
    }

    private func restoreSelectedBudgetGroup() {
        guard selectedBudgetGroup == nil else { return }
        guard !persistedSelectedBudgetGroupID.isEmpty else { return }

        guard let restoredGroup = budgetGroups.first(where: {
            $0.id.uuidString == persistedSelectedBudgetGroupID
        }) else {
            // The saved group may have been deleted or archived on another device.
            persistedSelectedBudgetGroupID = ""
            return
        }

        selectedBudgetGroup = restoredGroup
    }

    private func presentOnboardingIfNeeded() {
        guard !ProcessInfo.processInfo.arguments.contains("-ui-testing-skip-onboarding") else {
            return
        }
        let name = userSettings.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard name.isEmpty else { return }
        showingOnboarding = true
    }

    private func registerAppLaunchIfNeeded() {
        guard !showsOnboardingPreview, !hasCountedCurrentLaunch else { return }
        hasCountedCurrentLaunch = true
        appLaunchCount += 1

        guard appLaunchCount == 2 else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            requestReview()
        }
    }

    // MARK: - Hintergrund

    @ViewBuilder
    private func appBackground<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            #if os(iOS)
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            #else
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            #endif

            content()
        }
    }

    // MARK: - Akzentfarbe

    private var selectedAccentColor: Color {
        guard let settings = userSettings.first else {
            return ColorPreset.blue.color
        }

        let accentColor = AppAccentColor(
            rawValue: settings.accentColorRawValue
        ) ?? .blue

        switch accentColor {
        case .custom:
            return Color(
                hexString: settings.customAccentHex
            )

        default:
            return accentColor.color
                ?? ColorPreset.blue.color
        }
    }

    private var effectiveAccentColor: Color {
        selectedAccentColor
    }

    // MARK: - Erscheinungsbild

    private var preferredColorScheme: ColorScheme? {
        guard
            let rawValue =
                userSettings.first?.appearanceRawValue,
            let appearance =
                AppAppearance(rawValue: rawValue)
        else {
            return nil
        }

        return appearance.colorScheme
    }

    private var effectiveToolbarColorScheme: ColorScheme {
        preferredColorScheme ?? systemColorScheme
    }

    // MARK: - Tabbar-Aktualisierung

    private var tabViewAppearanceID: String {
        switch effectiveToolbarColorScheme {
        case .light:
            return "tabview-light"

        case .dark:
            return "tabview-dark"

        @unknown default:
            return "tabview-system"
        }
    }

    // MARK: - iOS Layout

    #if os(iOS)
    private var iOSLayout: some View {
        NavigationStack {
            TabView(selection: $selectedSection) {
                overviewTab
                transactionsTab
                budgetsTab
                savingsTab
                fixedCostsTab
            }
            .id(tabViewAppearanceID)
            .tint(effectiveAccentColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                sharedToolbar
            }
            .toolbarBackground(
                .visible,
                for: .navigationBar
            )
            .toolbarColorScheme(
                effectiveToolbarColorScheme,
                for: .navigationBar
            )
            .navigationDestination(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingOnboarding) {
                OnboardingView(group: selectedBudgetGroup)
            }
            .sheet(
                isPresented: $showingMonthPicker
            ) {
                MonthPickerSheet(
                    selectedDate: $selectedDate
                )
            }
            .sheet(
                isPresented: $showingBudgetEditor
            ) {
                BudgetEditorView(group: selectedBudgetGroup)
            }
            .sheet(
                isPresented: $showingBudgetManagement
            ) {
                BudgetManagementView()
            }
            .sheet(
                isPresented: $showingArchivedBudgets
            ) {
                ArchivedBudgetsView()
            }
            .sheet(
                isPresented: $showingTransactionEditor
            ) {
                TransactionEditorView(
                    initialDate: .now,
                    group: selectedBudgetGroup
                )
            }
        }
        .tint(effectiveAccentColor)
        .preferredColorScheme(
            preferredColorScheme
        )
    }
    #endif

    // MARK: - iOS Tabs

    #if os(iOS)
    private var overviewTab: some View {
        appBackground {
            OverviewView(selectedGroup: $selectedBudgetGroup, selectedDate: $selectedDate)
        }
        .tabItem {
            Label(
                AppSection.overview.title,
                systemImage:
                    AppSection.overview.icon
            )
        }
        .tag(AppSection.overview)
    }

    private var transactionsTab: some View {
        appBackground {
            TransactionsView(
                selectedDate: $selectedDate,
                selectedGroup: $selectedBudgetGroup,
                requestedToolbarAction: $requestedTransactionToolbarAction,
                onNewTransaction: { showingTransactionEditor = true }
            )
        }
        .tabItem {
            Label(
                AppSection.transactions.title,
                systemImage:
                    AppSection.transactions.icon
            )
        }
        .tag(AppSection.transactions)
    }

    private var budgetsTab: some View {
        appBackground {
            BudgetsView(
                showingBudgetEditor:
                    $showingBudgetEditor,
                selectedDate: $selectedDate,
                selectedGroup: $selectedBudgetGroup
            )
        }
        .tabItem {
            Label(
                AppSection.budgets.title,
                systemImage:
                    AppSection.budgets.icon
            )
        }
        .tag(AppSection.budgets)
    }

    private var savingsTab: some View {
        appBackground {
            SavingsView(
                addRequested: $requestingSavingsGoalEditor,
                reserveRequested: $requestingSavingsReserveEditor,
                managementRequested: $showingSavingsManagement,
                archiveRequested: $showingArchivedSavings,
                selectedDate: $selectedDate,
                selectedGroup: $selectedBudgetGroup
            )
        }
        .tabItem {
            Label(
                AppSection.savings.title,
                systemImage:
                    AppSection.savings.icon
            )
        }
        .tag(AppSection.savings)
    }

    private var fixedCostsTab: some View {
        appBackground {
            FixedCostsView(
                addRequested: $requestingFixedCostEditor,
                selectedGroup: $selectedBudgetGroup
            )
        }
        .tabItem {
            Label(
                AppSection.fixcosts.title,
                systemImage:
                    AppSection.fixcosts.icon
            )
        }
        .tag(AppSection.fixcosts)
    }
    #endif

    // MARK: - macOS Layout

    #if os(macOS)
    private var macLayout: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack {
                selectedSectionView
                    .navigationTitle(
                        selectedSection.title
                    )
                    .toolbar {
                        sharedToolbar
                    }
                    .navigationDestination(isPresented: $showingSettings) {
                        SettingsView()
                    }
                    .sheet(isPresented: $showingOnboarding) {
                        OnboardingView(group: selectedBudgetGroup)
                    }
                    .sheet(
                        isPresented:
                            $showingMonthPicker
                    ) {
                        MonthPickerSheet(
                            selectedDate:
                                $selectedDate
                        )
                    }
                    .sheet(
                        isPresented:
                            $showingBudgetEditor
                    ) {
                        BudgetEditorView(group: selectedBudgetGroup)
                    }
                    .sheet(
                        isPresented:
                            $showingBudgetManagement
                    ) {
                        BudgetManagementView()
                    }
                    .sheet(
                        isPresented:
                            $showingArchivedBudgets
                    ) {
                        ArchivedBudgetsView()
                    }
                    .sheet(
                        isPresented: $showingTransactionEditor
                    ) {
                        TransactionEditorView(initialDate: .now)
                    }
            }
        }
        .tint(effectiveAccentColor)
        .preferredColorScheme(
            preferredColorScheme
        )
    }
    #endif

    // MARK: - macOS Seitenleiste

    #if os(macOS)
    private var sidebar: some View {
        List(
            AppSection.allCases,
            selection: $selectedSection
        ) { section in
            Label(
                section.title,
                systemImage: section.icon
            )
            .tag(section)
        }
        .navigationTitle("Elyra Budget")
        .navigationSplitViewColumnWidth(
            min: 180,
            ideal: 220
        )
    }
    #endif

    // MARK: - Gemeinsame Toolbar

    @ToolbarContentBuilder
    private var sharedToolbar: some ToolbarContent {
        ToolbarItem(placement: budgetGroupToolbarPlacement) {
            BudgetGroupMenu(
                selection: $selectedBudgetGroup,
                groups: budgetGroups,
                manage: { showingBudgetGroupManagement = true },
                settings: { showingSettings = true }
            )
        }

        ToolbarItem(
            placement: .principal
        ) {
            MonthNavigationControl(
                title: monthTitle,
                onPrevious: {
                    moveSelectedMonth(by: -1)
                },
                onSelectDate: {
                    showingMonthPicker = true
                },
                onNext: {
                    moveSelectedMonth(by: 1)
                }
            )
            .tint(effectiveAccentColor)
        }

        ToolbarItem(
            placement: .primaryAction
        ) {
            if selectedSection == .overview {
                overviewActionsMenu
            } else if selectedSection == .transactions {
                transactionActionsMenu
            } else if selectedSection == .budgets {
                budgetActionsMenu
            } else if selectedSection == .savings {
                savingsActionsMenu
            } else {
                standardAddButton
            }
        }
    }

    private var budgetGroupToolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    // MARK: - Budget-Menü

    private var overviewActionsMenu: some View {
        Menu {
            Button { showingTransactionEditor = true } label: {
                Label("Neue Buchung", systemImage: "arrow.up.right")
            }
            Button { showingBudgetEditor = true } label: {
                Label("Neues Budget", systemImage: "chart.bar.fill")
            }
            Button { requestingFixedCostEditor = true } label: {
                Label("Neue Fixkosten", systemImage: "calendar.badge.clock")
            }
            Button { requestingSavingsGoalEditor = true } label: {
                Label("Neues Sparziel", systemImage: "target")
            }
            Button { requestingSavingsReserveEditor = true } label: {
                Label("Neue freie Rücklage", systemImage: "banknote")
            }
        } label: {
            Image(systemName: "plus")
                .foregroundStyle(effectiveAccentColor)
        }
        .help("Schnellaktionen")
        .accessibilityLabel("Schnellaktionen")
    }

    private var transactionActionsMenu: some View {
        Menu {
            Button {
                showingTransactionEditor = true
            } label: {
                Label("Neue Buchung", systemImage: "plus.circle.fill")
            }

            Button {
                requestedTransactionToolbarAction = .exportCSV
            } label: {
                Label("CSV exportieren", systemImage: "tablecells")
            }

            Button {
                requestedTransactionToolbarAction = .exportPDF
            } label: {
                Label("PDF exportieren", systemImage: "doc.richtext")
            }

            Button {
                requestedTransactionToolbarAction = .importCSV
            } label: {
                Label("CSV importieren", systemImage: "square.and.arrow.down")
            }

            Button {
                requestedTransactionToolbarAction = .recurringTransactions
            } label: {
                Label("Wiederkehrende Buchungen", systemImage: "arrow.triangle.2.circlepath")
            }
        } label: {
            Image(systemName: "plus")
                .foregroundStyle(effectiveAccentColor)
        }
        .help("Buchungsaktionen")
        .accessibilityLabel("Buchungsaktionen")
    }

    private var budgetActionsMenu: some View {
        Menu {
            Button {
                showingBudgetEditor = true
            } label: {
                Label(
                    "Neues Budget",
                    systemImage: "plus"
                )
            }

            Button {
                showingBudgetManagement = true
            } label: {
                Label(
                    "Budgets verwalten",
                    systemImage: "arrow.up.arrow.down"
                )
            }

            Divider()

            Button {
                showingArchivedBudgets = true
            } label: {
                Label(
                    "Archivierte Budgets",
                    systemImage: "archivebox"
                )
            }
        } label: {
            Image(systemName: "plus")
                .foregroundStyle(
                    effectiveAccentColor
                )
        }
        .help("Budgetaktionen")
        .accessibilityLabel(
            "Budgetaktionen"
        )
    }

    // MARK: - Sparen-Menü

    private var savingsActionsMenu: some View {
        Menu {
            Button {
                requestingSavingsGoalEditor = true
            } label: {
                Label("Neues Sparziel", systemImage: "target")
            }

            Button {
                requestingSavingsReserveEditor = true
            } label: {
                Label("Neue freie Rücklage", systemImage: "banknote")
            }

            Button {
                showingSavingsManagement = true
            } label: {
                Label("Verwalten", systemImage: "arrow.up.arrow.down")
            }

            Divider()

            Button {
                showingArchivedSavings = true
            } label: {
                Label("Archiv", systemImage: "archivebox")
            }
        } label: {
            Image(systemName: "plus")
                .foregroundStyle(effectiveAccentColor)
        }
        .help("Sparaktionen")
        .accessibilityLabel("Sparaktionen")
    }

    // MARK: - Standardmäßiger Plus-Button

    private var standardAddButton: some View {
        Button {
            handleAddButton()
        } label: {
            Image(systemName: "plus")
                .foregroundStyle(
                    effectiveAccentColor
                )
        }
        .help(addButtonHelpText)
        .accessibilityLabel(
            addButtonAccessibilityLabel
        )
    }

    // MARK: - Hinzufügen

    private func handleAddButton() {
        switch selectedSection {
        case .budgets:
            showingBudgetEditor = true

        case .transactions:
            showingTransactionEditor = true

        case .fixcosts:
            requestingFixedCostEditor = true

        case .savings:
            requestingSavingsGoalEditor = true

        case .overview:
            break
        }
    }

    private var addButtonHelpText:
        LocalizedStringResource {
        switch selectedSection {
        case .transactions:
            return "Neue Buchung"

        case .budgets:
            return "Neues Budget"

        case .fixcosts:
            return "Neue Fixkosten"

        case .savings:
            return "Sparen hinzufügen"

        default:
            return "Neues Element"
        }
    }

    private var addButtonAccessibilityLabel:
        LocalizedStringResource {
        switch selectedSection {
        case .transactions:
            return "Neue Buchung erstellen"

        case .budgets:
            return "Neues Budget erstellen"

        case .fixcosts:
            return "Fixkosten erstellen"

        case .savings:
            return "Sparen hinzufügen"

        default:
            return "Neues Element erstellen"
        }
    }
    // MARK: - macOS Seitenauswahl

    @ViewBuilder
    private var selectedSectionView: some View {
        switch selectedSection {
        case .overview:
            OverviewView(selectedGroup: $selectedBudgetGroup, selectedDate: $selectedDate)

        case .transactions:
            TransactionsView(
                selectedDate: $selectedDate,
                selectedGroup: $selectedBudgetGroup
            )

        case .budgets:
            BudgetsView(
                showingBudgetEditor:
                    $showingBudgetEditor,
                selectedDate: $selectedDate,
                selectedGroup: $selectedBudgetGroup
            )

        case .savings:
            SavingsView(
                addRequested: $requestingSavingsGoalEditor,
                reserveRequested: $requestingSavingsReserveEditor,
                managementRequested: $showingSavingsManagement,
                archiveRequested: $showingArchivedSavings,
                selectedDate: $selectedDate,
                selectedGroup: $selectedBudgetGroup
            )

        case .fixcosts:
            FixedCostsView(
                addRequested: $requestingFixedCostEditor,
                selectedGroup: $selectedBudgetGroup
            )
        }
    }

    // MARK: - Monatsnavigation

    private var monthTitle: String {
        selectedDate.formatted(
            .dateTime
                .month(.wide)
                .year()
        )
    }

    private func moveSelectedMonth(
        by months: Int
    ) {
        guard let newDate = Calendar.current.date(
            byAdding: .month,
            value: months,
            to: selectedDate
        ) else {
            return
        }

//        withAnimation {
            selectedDate = newDate
//        }
    }
}

// MARK: - Previews

#Preview("Free – Deutsch") {
    ContentView()
        .environment(
            ProAccessManager()
        )
        .environment(AppLockManager())
        .environment(CloudKitSyncMonitor(environment: ["ELYRA_BUDGET_USE_CLOUDKIT": "NO"]))
        .modelContainer(
            for: [
                UserSettings.self,
                BudgetGroup.self,
                Budget.self,
                Transaction.self,
                FixedCost.self,
                SavingsGoal.self,
                SavingsContribution.self
            ],
            inMemory: true
        )
        .environment(
            \.locale,
            Locale(identifier: "de")
        )
}

#Preview("Onboarding – ContentView") {
    ContentView(showsOnboardingPreview: true)
        .environment(ProAccessManager())
        .environment(AppLockManager())
        .environment(CloudKitSyncMonitor(environment: ["ELYRA_BUDGET_USE_CLOUDKIT": "NO"]))
        .modelContainer(
            for: [
                UserSettings.self,
                BudgetGroup.self,
                Budget.self,
                Transaction.self,
                FixedCost.self,
                SavingsGoal.self,
                SavingsContribution.self
            ],
            inMemory: true
        )
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Pro – Deutsch") {
    let proAccess = ProAccessManager()
    proAccess.hasPro = true

    return ContentView()
        .environment(proAccess)
        .environment(AppLockManager())
        .environment(CloudKitSyncMonitor(environment: ["ELYRA_BUDGET_USE_CLOUDKIT": "NO"]))
        .modelContainer(
            for: [
                UserSettings.self,
                BudgetGroup.self,
                Budget.self,
                Transaction.self,
                FixedCost.self,
                SavingsGoal.self,
                SavingsContribution.self
            ],
            inMemory: false
        )
        .environment(
            \.locale,
            Locale(identifier: "de")
        )
}

#Preview("Free – English") {
    ContentView()
        .environment(
            ProAccessManager()
        )
        .environment(AppLockManager())
        .environment(CloudKitSyncMonitor(environment: ["ELYRA_BUDGET_USE_CLOUDKIT": "NO"]))
        .modelContainer(
            for: [
                UserSettings.self,
                BudgetGroup.self,
                Budget.self,
                Transaction.self,
                FixedCost.self,
                SavingsGoal.self,
                SavingsContribution.self
            ],
            inMemory: true
        )
        .environment(
            \.locale,
            Locale(identifier: "en")
        )
}

#Preview("Pro – English") {
    let proAccess = ProAccessManager()
    proAccess.hasPro = true

    return ContentView()
        .environment(proAccess)
        .environment(AppLockManager())
        .environment(CloudKitSyncMonitor(environment: ["ELYRA_BUDGET_USE_CLOUDKIT": "NO"]))
        .modelContainer(
            for: [
                UserSettings.self,
                BudgetGroup.self,
                Budget.self,
                Transaction.self,
                FixedCost.self,
                SavingsGoal.self,
                SavingsContribution.self
            ],
            inMemory: true
        )
        .environment(
            \.locale,
            Locale(identifier: "en")
        )
}
