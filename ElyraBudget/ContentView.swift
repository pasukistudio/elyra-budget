import SwiftUI
import SwiftData

struct ContentView: View {

    // MARK: - SwiftData

    @Query private var userSettings: [UserSettings]

    // MARK: - Navigation & Sheet States

    @State private var selectedSection: SidebarSection = .overview
    @State private var selectedDate = Date()

    @State private var showingMonthPicker = false
    @State private var showingBudgetEditor = false

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

    private var selectedAccentColor: Color? {
        guard let settings = userSettings.first else {
            return nil
        }

        let accentColor = AppAccentColor(
            rawValue: settings.accentColorRawValue
        ) ?? .system

        switch accentColor {
        case .system:
            return nil

        case .custom:
            return Color(
                hexString: settings.customAccentHex
            )

        default:
            return accentColor.color
        }
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

    // MARK: - Hauptansicht

    var body: some View {
#if os(macOS)

        macLayout

#else

        iOSLayout

#endif
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                sharedToolbar
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
                BudgetEditorView()
            }
        }
        .tint(selectedAccentColor)
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
                SidebarSection.overview.title,
                systemImage:
                    SidebarSection.overview.icon
            )
        }
        .tag(SidebarSection.overview)
    }

    private var transactionsTab: some View {
        appBackground {
            TransactionsView()
        }
        .tabItem {
            Label(
                SidebarSection.transactions.title,
                systemImage:
                    SidebarSection.transactions.icon
            )
        }
        .tag(SidebarSection.transactions)
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
                SidebarSection.budgets.title,
                systemImage:
                    SidebarSection.budgets.icon
            )
        }
        .tag(SidebarSection.budgets)
    }

    private var savingsTab: some View {
        appBackground {
            SavingsView()
        }
        .tabItem {
            Label(
                SidebarSection.savings.title,
                systemImage:
                    SidebarSection.savings.icon
            )
        }
        .tag(SidebarSection.savings)
    }

    private var fixedCostsTab: some View {
        appBackground {
            FixedCostsView()
        }
        .tabItem {
            Label(
                SidebarSection.fixcosts.title,
                systemImage:
                    SidebarSection.fixcosts.icon
            )
        }
        .tag(SidebarSection.fixcosts)
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
            }
        }
        .tint(selectedAccentColor)
        .preferredColorScheme(
            preferredColorScheme
        )
    }
#endif

    // MARK: - macOS Seitenleiste

#if os(macOS)
    private var sidebar: some View {
        List(
            SidebarSection.allCases,
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
            }
            .accessibilityLabel(
                "Profil und Einstellungen"
            )
        }
#endif

        ToolbarItem(placement: .principal) {
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
        }

        ToolbarItem(
            placement: .primaryAction
        ) {
            Button {
                handleAddButton()
            } label: {
                Image(systemName: "plus")
            }
            .help(addButtonHelpText)
            .accessibilityLabel(
                addButtonAccessibilityLabel
            )
        }
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

    private var isShowingCurrentMonth: Bool {
        Calendar.current.isDate(
            selectedDate,
            equalTo: Date(),
            toGranularity: .month
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

        withAnimation {
            selectedDate = newDate
        }
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
                Budget.self
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
                Budget.self
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
                Budget.self
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
                Budget.self
            ],
            inMemory: true
        )
        .environment(
            \.locale,
            Locale(identifier: "en")
        )
}
