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

    @State private var editingFixedCost: FixedCost?
    @State private var showingEditor = false
    @State private var fixedCostToDelete: FixedCost?
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
            } else {
                content
            }
        }
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
        do { try modelContext.save() }
        catch { saveErrorMessage = error.localizedDescription }
        fixedCostToDelete = nil
    }

    private func book(_ item: FixedCostDueItem) {
        let transaction = Transaction(
            title: item.fixedCost.title,
            amount: item.fixedCost.amount,
            date: item.dueDate,
            note: item.fixedCost.note,
            type: .expense,
            budget: item.fixedCost.budget,
            group: item.fixedCost.group ?? item.fixedCost.budget?.group
        )
        transaction.fixedCostID = item.fixedCost.id
        transaction.fixedCostOccurrenceDate = item.dueDate
        modelContext.insert(transaction)
        do { try modelContext.save() }
        catch { saveErrorMessage = error.localizedDescription }
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

#Preview {
    FixedCostsView()
        .modelContainer(for: [UserSettings.self, BudgetGroup.self, Budget.self, Transaction.self, FixedCost.self], inMemory: true)
}
