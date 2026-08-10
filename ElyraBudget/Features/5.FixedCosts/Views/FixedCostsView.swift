import SwiftData
import SwiftUI

struct FixedCostsView: View {
    @Binding private var addRequested: Bool
    @Binding private var selectedGroup: BudgetGroup?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCurrencyCode) private var currencyCode

    @Query(sort: [SortDescriptor<FixedCost>(\.createdAt)])
    private var fixedCosts: [FixedCost]

    @Query(
        filter: #Predicate<Budget> { !$0.isArchived },
        sort: [
            SortDescriptor<Budget>(\.sortOrder),
            SortDescriptor<Budget>(\.createdAt)
        ]
    )
    private var budgets: [Budget]

    @Query(sort: [SortDescriptor<Transaction>(\.date)])
    private var transactions: [Transaction]

    @Query(sort: [SortDescriptor<SavingsGoal>(\.createdAt)])
    private var savingsGoals: [SavingsGoal]

    @State private var editingFixedCost: FixedCost?
    @State private var showingEditor = false
    @State private var savingsGoalFromFixedCost: FixedCost?
    @State private var showingSavingsGoalEditor = false
    @State private var fixedCostToDelete: FixedCost?
    @State private var historyFixedCost: FixedCost?
    @State private var saveErrorMessage: String?

    init(
        addRequested: Binding<Bool> = .constant(false),
        selectedGroup: Binding<BudgetGroup?> = .constant(nil)
    ) {
        _addRequested = addRequested
        _selectedGroup = selectedGroup
    }

    private var visibleFixedCosts: [FixedCost] {
        guard let selectedGroup else { return fixedCosts }
        return fixedCosts.filter { $0.group === selectedGroup }
    }

    private var visibleBudgets: [Budget] {
        guard let selectedGroup else { return budgets }
        return budgets.filter { $0.group === selectedGroup }
    }

    private var activeCosts: [FixedCost] { visibleFixedCosts.filter { !$0.isPaused } }
    private var pausedCosts: [FixedCost] { visibleFixedCosts.filter(\.isPaused) }

    private var monthlyAverage: Decimal {
        visibleFixedCosts.filter { !$0.isPaused }.reduce(.zero) { $0 + $1.monthlyEquivalent }
    }

    private var yearlyAverage: Decimal { monthlyAverage * 12 }

    private var pendingItems: [FixedCostDueItem] {
        FixedCostScheduler.pendingManualBookings(
            fixedCosts: visibleFixedCosts,
            transactions: transactions
        )
    }

    var body: some View {
        Group {
            if visibleFixedCosts.isEmpty {
                emptyState
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                content
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.3), value: visibleFixedCosts.isEmpty)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingFixedCost = nil
                    showingEditor = true
                } label: {
                    Label("Fixkosten hinzufügen", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            FixedCostEditorView(fixedCost: editingFixedCost, budgets: visibleBudgets, group: selectedGroup)
        }
        .sheet(isPresented: $showingSavingsGoalEditor) {
            SavingsGoalEditorView(
                goal: nil,
                budgets: visibleBudgets,
                type: .goal,
                group: selectedGroup,
                linkedFixedCost: savingsGoalFromFixedCost
            )
        }
        .sheet(item: $historyFixedCost) { fixedCost in
            FixedCostHistoryView(fixedCost: fixedCost, transactions: transactions)
        }
        .alert(
            "Fixkosten löschen?",
            isPresented: deleteConfirmationIsPresented,
            presenting: fixedCostToDelete
        ) { fixedCost in
            Button("Löschen", role: .destructive) { delete(fixedCost) }
            Button("Abbrechen", role: .cancel) { fixedCostToDelete = nil }
        } message: { fixedCost in
            Text("„\(fixedCost.title)“ wird dauerhaft gelöscht.")
        }
        .saveErrorAlert(message: $saveErrorMessage)
        .onChange(of: addRequested) { _, requested in
            guard requested else { return }
            editingFixedCost = nil
            showingEditor = true
            addRequested = false
        }
    }

    private var content: some View {
        List {
            Section { summary }

            if !pendingItems.isEmpty {
                Section("Fällig") {
                    ForEach(pendingItems) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.fixedCost.title).font(.headline)
                                Text(item.dueDate, format: .dateTime.day().month().year())
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Jetzt buchen") { book(item) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }

            Section("Aktiv") {
                ForEach(activeCosts) { fixedCost in
                    FixedCostRowView(fixedCost: fixedCost, currencyCode: currencyCode)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingFixedCost = fixedCost
                            showingEditor = true
                        }
                        .contextMenu {
                            Button {
                                historyFixedCost = fixedCost
                            } label: {
                                Label("Verlauf anzeigen", systemImage: "clock.arrow.circlepath")
                            }
                            Button {
                                savingsGoalFromFixedCost = fixedCost
                                showingSavingsGoalEditor = true
                            } label: {
                                Label("Sparziel anlegen", systemImage: "banknote")
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { fixedCostToDelete = fixedCost } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                }
            }

            if !pausedCosts.isEmpty {
                Section("Pausiert") {
                    ForEach(pausedCosts) { fixedCost in
                        FixedCostRowView(fixedCost: fixedCost, currencyCode: currencyCode)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingFixedCost = fixedCost
                                showingEditor = true
                            }
                            .contextMenu {
                                Button {
                                    historyFixedCost = fixedCost
                                } label: {
                                    Label("Verlauf anzeigen", systemImage: "clock.arrow.circlepath")
                                }
                                Button {
                                    savingsGoalFromFixedCost = fixedCost
                                    showingSavingsGoalEditor = true
                                } label: {
                                    Label("Sparziel anlegen", systemImage: "banknote")
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) { fixedCostToDelete = fixedCost } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Übersicht").font(.headline)
            HStack {
                summaryValue("Monatlich", monthlyAverage)
                Spacer()
                summaryValue("Jährlich", yearlyAverage)
            }
        }
        .padding(.vertical, 4)
    }

    private func summaryValue(_ title: String, _ value: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value, format: .currency(code: currencyCode)).font(.title3.bold())
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Noch keine Fixkosten", systemImage: "calendar.badge.clock")
        } description: {
            Text("Lege regelmäßige Ausgaben an und behalte deine monatliche Belastung im Blick.")
        } actions: {
            Button("Fixkosten hinzufügen") {
                editingFixedCost = nil
                showingEditor = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var deleteConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { fixedCostToDelete != nil },
            set: { if !$0 { fixedCostToDelete = nil } }
        )
    }

    private func delete(_ fixedCost: FixedCost) {
        modelContext.delete(fixedCost)
        do {
            try modelContext.save()
            rescheduleNotifications()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
        fixedCostToDelete = nil
    }

    private func book(_ item: FixedCostDueItem) {
        do {
            try FixedCostScheduler.book(
                fixedCost: item.fixedCost,
                dueDate: item.dueDate,
                savingsGoals: savingsGoals,
                modelContext: modelContext
            )
            rescheduleNotifications()
        }
        catch { saveErrorMessage = error.localizedDescription }
    }

    private func rescheduleNotifications() {
        let allFixedCosts = (try? modelContext.fetch(
            FetchDescriptor<FixedCost>(sortBy: [SortDescriptor(\.createdAt)])
        )) ?? fixedCosts
        let allTransactions = (try? modelContext.fetch(
            FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date)])
        )) ?? transactions

        Task {
            await FixedCostNotificationScheduler.reschedule(
                fixedCosts: allFixedCosts,
                transactions: allTransactions
            )
        }
    }
}

private struct FixedCostRowView: View {
    let fixedCost: FixedCost
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: fixedCost.budget?.iconName ?? "calendar.badge.clock")
                .font(.title3)
                .foregroundStyle(
                    fixedCost.budget.map {
                        Color(hexString: $0.iconColorHex)
                    } ?? .accentColor
                )
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(fixedCost.title).font(.headline)
                Text(fixedCost.frequency.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(fixedCost.schedule.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(fixedCost.amount, format: .currency(code: currencyCode))
                    .font(.headline)
                if let nextDate = fixedCost.nextDueDate() {
                    Text(nextDate, format: .dateTime.day().month())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(fixedCost.isPaused ? 0.6 : 1)
    }

}

private struct FixedCostHistoryView: View {
    let fixedCost: FixedCost
    let transactions: [Transaction]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appCurrencyCode) private var currencyCode

    private var occurrences: [FixedCostOccurrence] {
        FixedCostScheduler.history(for: fixedCost, transactions: transactions)
    }

    var body: some View {
        NavigationStack {
            Group {
                if occurrences.isEmpty {
                    ContentUnavailableView(
                        "Noch keine Vorkommen",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Für diese Fixkosten wurden noch keine Buchungen oder geplanten Termine gefunden.")
                    )
                } else {
                    List(occurrences) { occurrence in
                        HStack(spacing: 12) {
                            Image(systemName: iconName(for: occurrence))
                                .foregroundStyle(color(for: occurrence))
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(occurrence.dueDate, format: .dateTime.day().month().year())
                                    .font(.headline)
                                Text(statusText(for: occurrence))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if let transaction = occurrence.transaction {
                                Text(transaction.amount, format: .currency(code: currencyCode))
                                    .font(.headline)
                            } else {
                                Text(fixedCost.amount, format: .currency(code: currencyCode))
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(fixedCost.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    private func iconName(for occurrence: FixedCostOccurrence) -> String {
        switch occurrence.status {
        case .booked: "checkmark.circle.fill"
        case .due: "exclamationmark.circle.fill"
        case .scheduled: "calendar"
        }
    }

    private func color(for occurrence: FixedCostOccurrence) -> Color {
        switch occurrence.status {
        case .booked: .green
        case .due: .orange
        case .scheduled: .secondary
        }
    }

    private func statusText(for occurrence: FixedCostOccurrence) -> String {
        switch occurrence.status {
        case .due: "Fällig – manuelle Buchung ausstehend"
        case .scheduled: "Geplant"
        case .booked:
            switch occurrence.transaction?.fixedCostBookingAutomatic {
            case true: "Automatisch gebucht"
            case false: "Manuell gebucht"
            case nil: "Gebucht"
            }
        }
    }
}

#Preview {
    FixedCostsView()
        .modelContainer(for: [UserSettings.self, BudgetGroup.self, BudgetGroupMonthlyAllocation.self, Budget.self, Transaction.self, FixedCost.self], inMemory: true)
}
