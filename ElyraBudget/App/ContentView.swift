import SwiftData
import SwiftUI

struct ContentView: View {

    // MARK: - SwiftData

    @Query private var userSettings: [UserSettings]

    // MARK: - Environment

    @Environment(\.colorScheme)
    private var systemColorScheme

    // MARK: - Navigation & Sheets

    @State private var selectedSection: AppSection = .overview
    @State private var selectedDate = Date()

    @State private var showingMonthPicker = false
    @State private var showingBudgetEditor = false
    @State private var showingBudgetManagement = false
    @State private var showingArchivedBudgets = false

    // MARK: - Hauptansicht

    var body: some View {
        #if os(macOS)
        macLayout
        #else
        iOSLayout
        #endif
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
                BudgetEditorView()
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
            OverviewView()
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
            TransactionsView()
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
                    $showingBudgetEditor
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
            SavingsView()
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
            FixedCostsView()
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
                        BudgetEditorView()
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
        #if os(iOS)
        ToolbarItem(
            placement: .topBarLeading
        ) {
            NavigationLink {
                SettingsView()
            } label: {
                Image(
                    systemName:
                        "person.crop.circle.fill"
                )
                .foregroundStyle(
                    effectiveAccentColor
                )
            }
            .accessibilityLabel(
                "Profil und Einstellungen"
            )
        }
        #endif

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
            if selectedSection == .budgets {
                budgetActionsMenu
            } else {
                standardAddButton
            }
        }
    }

    // MARK: - Budget-Menü

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

        case .overview,
             .transactions,
             .savings,
             .fixcosts:
            break
        }
    }

    private var addButtonHelpText:
        LocalizedStringResource {
        switch selectedSection {
        case .budgets:
            return "Neues Budget"

        default:
            return "Neues Element"
        }
    }

    private var addButtonAccessibilityLabel:
        LocalizedStringResource {
        switch selectedSection {
        case .budgets:
            return "Neues Budget erstellen"

        default:
            return "Neues Element erstellen"
        }
    }

    // MARK: - macOS Seitenauswahl

    @ViewBuilder
    private var selectedSectionView: some View {
        switch selectedSection {
        case .overview:
            OverviewView()

        case .transactions:
            TransactionsView()

        case .budgets:
            BudgetsView(
                showingBudgetEditor:
                    $showingBudgetEditor
            )

        case .savings:
            SavingsView()

        case .fixcosts:
            FixedCostsView()
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
        .modelContainer(
            for: [
                UserSettings.self,
                Budget.self,
                Transaction.self
            ],
            inMemory: true
        )
        .environment(
            \.locale,
            Locale(identifier: "de")
        )
}

#Preview("Pro – Deutsch") {
    let proAccess = ProAccessManager()
    proAccess.hasPro = true

    return ContentView()
        .environment(proAccess)
        .modelContainer(
            for: [
                UserSettings.self,
                Budget.self,
                Transaction.self
            ],
            inMemory: true
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
        .modelContainer(
            for: [
                UserSettings.self,
                Budget.self,
                Transaction.self
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
        .modelContainer(
            for: [
                UserSettings.self,
                Budget.self,
                Transaction.self
            ],
            inMemory: true
        )
        .environment(
            \.locale,
            Locale(identifier: "en")
        )
}
