import SwiftData
import SwiftUI

struct SavingsView: View {
    @Binding private var addRequested: Bool
    @Binding private var reserveRequested: Bool
    @Binding private var managementRequested: Bool
    @Binding private var archiveRequested: Bool
    @Binding private var selectedDate: Date
    @Binding private var selectedGroup: BudgetGroup?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCurrencyCode) private var currencyCode

    @Query(
        filter: #Predicate<SavingsGoal> { !$0.isArchived },
        sort: [
            SortDescriptor<SavingsGoal>(\.sortOrder),
            SortDescriptor<SavingsGoal>(\.createdAt)
        ]
    )
    private var goals: [SavingsGoal]

    @Query(filter: #Predicate<SavingsGoal> { $0.isArchived })
    private var archivedGoals: [SavingsGoal]

    @Query(
        filter: #Predicate<Budget> { !$0.isArchived },
        sort: [
            SortDescriptor<Budget>(\.sortOrder),
            SortDescriptor<Budget>(\.createdAt)
        ]
    )
    private var budgets: [Budget]

    @State private var editingGoal: SavingsGoal?
    @State private var editorType: SavingsGoalType = .goal
    @State private var showingEditor = false
    @State private var showingManagement = false
    @State private var showingArchived = false
    @State private var contributingGoal: SavingsGoal?
    @State private var detailGoal: SavingsGoal?
    @State private var goalToArchive: SavingsGoal?
    @State private var goalToDelete: SavingsGoal?
    @State private var saveErrorMessage: String?

    init(
        addRequested: Binding<Bool> = .constant(false),
        reserveRequested: Binding<Bool> = .constant(false),
        managementRequested: Binding<Bool> = .constant(false),
        archiveRequested: Binding<Bool> = .constant(false),
        selectedDate: Binding<Date> = .constant(.now),
        selectedGroup: Binding<BudgetGroup?> = .constant(nil)
    ) {
        _addRequested = addRequested
        _reserveRequested = reserveRequested
        _managementRequested = managementRequested
        _archiveRequested = archiveRequested
        _selectedDate = selectedDate
        _selectedGroup = selectedGroup
    }

    private var selectedMonthEnd: Date {
        let calendar = Calendar.autoupdatingCurrent
        let interval = calendar.dateInterval(of: .month, for: selectedDate)
        return interval?.end.addingTimeInterval(-1) ?? selectedDate
    }

    private var groupedGoals: [SavingsGoal] {
        guard let selectedGroup else { return goals }
        return goals.filter { $0.group === selectedGroup }
    }

    private var visibleGoals: [SavingsGoal] {
        groupedGoals.filter { $0.createdAt <= selectedMonthEnd }
    }

    private var visibleArchivedGoals: [SavingsGoal] {
        guard let selectedGroup else { return archivedGoals }
        return archivedGoals.filter { $0.group === selectedGroup }
    }

    private var visibleBudgets: [Budget] {
        guard let selectedGroup else { return budgets }
        return budgets.filter { $0.group === selectedGroup }
    }

    var body: some View {
        Group {
            if visibleGoals.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .sheet(isPresented: $showingEditor) {
            if editorType == .goal {
                SavingsGoalEditorView(goal: editingGoal, budgets: visibleBudgets, type: .goal, group: selectedGroup)
            } else {
                FreeReserveEditorView(reserve: editingGoal, budgets: visibleBudgets, group: selectedGroup)
            }
        }
        .sheet(isPresented: $showingManagement) {
            SavingsManagementView(goals: groupedGoals, archivedGoals: visibleArchivedGoals, budgets: visibleBudgets)
        }
        .sheet(isPresented: $showingArchived) {
            ArchivedSavingsView(goals: visibleArchivedGoals)
        }
        .sheet(item: $contributingGoal) { goal in
            SavingsContributionEditorView(goal: goal, budgets: visibleBudgets)
        }
        .sheet(item: $detailGoal) { goal in
            SavingsGoalDetailView(
                goal: goal,
                currencyCode: currencyCode,
                onEdit: {
                    detailGoal = nil
                    editingGoal = goal
                    editorType = goal.type
                    showingEditor = true
                },
                onContribute: {
                    detailGoal = nil
                    contributingGoal = goal
                }
            )
        }
        .alert(
            "In den Archiv verschieben?",
            isPresented: archiveConfirmationIsPresented,
            presenting: goalToArchive
        ) { goal in
            Button("Archivieren") { archive(goal) }
            Button("Abbrechen", role: .cancel) { goalToArchive = nil }
        } message: { goal in
            Text("„\(goal.name)“ bleibt erhalten und kann später im Archiv wiederhergestellt werden.")
        }
        .alert(
            "Sparziel löschen?",
            isPresented: deleteConfirmationIsPresented,
            presenting: goalToDelete
        ) { goal in
            Button("Löschen", role: .destructive) { delete(goal) }
            Button("Abbrechen", role: .cancel) { goalToDelete = nil }
        } message: { goal in
            Text("„\(goal.name)“ und seine Einzahlungen werden dauerhaft gelöscht.")
        }
        .saveErrorAlert(message: $saveErrorMessage)
        .task {
            migrateLegacyGoals()
        }
        .onChange(of: addRequested) { _, requested in
            guard requested else { return }
            openEditor(for: .goal)
            addRequested = false
        }
        .onChange(of: reserveRequested) { _, requested in
            guard requested else { return }
            openEditor(for: .reserve)
            reserveRequested = false
        }
        .onChange(of: managementRequested) { _, requested in
            guard requested else { return }
            showingManagement = true
            managementRequested = false
        }
        .onChange(of: archiveRequested) { _, requested in
            guard requested else { return }
            showingArchived = true
            archiveRequested = false
        }
    }

    private var content: some View {
        List {
            let activeGoals = visibleGoals.filter { $0.type == .goal }
            let reserves = visibleGoals.filter { $0.type == .reserve }

            if !activeGoals.isEmpty {
                Section("Sparziele") { }
                ForEach(activeGoals) { goal in
                    Section { goalRow(goal) }
                }
            }
            if !reserves.isEmpty {
                Section("Freie Rücklagen") { }
                ForEach(reserves) { goal in
                    Section { goalRow(goal) }
                }
            }
            if visibleGoals.isEmpty {
                Section {
                    Text("Noch keine aktiven Sparziele oder freien Rücklagen.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
    }

    @ViewBuilder
    private func goalRow(_ goal: SavingsGoal) -> some View {
        SavingsGoalCardView(
            goal: goal,
            currencyCode: currencyCode,
            asOf: selectedMonthEnd,
            contribute: { contributingGoal = goal }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            detailGoal = goal
        }
        .contextMenu {
            Button {
                editingGoal = goal
                editorType = goal.type
                showingEditor = true
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }

            Button {
                goalToArchive = goal
            } label: {
                Label("Archivieren", systemImage: "archivebox")
            }

            Divider()

            Button(role: .destructive) {
                goalToDelete = goal
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .swipeActions {
            Button {
                goalToArchive = goal
            } label: {
                Label("Archivieren", systemImage: "archivebox")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Noch keine Sparziele", systemImage: "banknote")
        } description: {
            Text("Lege Sparziele oder freie Rücklagen an und behalte deine Fortschritte im Blick.")
        } actions: {
            Menu("Hinzufügen") {
                Button("Neues Sparziel") { openEditor(for: .goal) }
                Button("Neue freie Rücklage") { openEditor(for: .reserve) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var archiveConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { goalToArchive != nil },
            set: { if !$0 { goalToArchive = nil } }
        )
    }

    private var deleteConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { goalToDelete != nil },
            set: { if !$0 { goalToDelete = nil } }
        )
    }

    private func moveGoals(from source: IndexSet, to destination: Int) {
        var reordered = goals
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, goal) in reordered.enumerated() {
            goal.sortOrder = index
            goal.updatedAt = .now
        }
        do { try modelContext.save() }
        catch { saveErrorMessage = error.localizedDescription }
    }

    private func openEditor(for type: SavingsGoalType) {
        editingGoal = nil
        editorType = type
        showingEditor = true
    }

    private func migrateLegacyGoals() {
        let legacyGoals = goals.filter { $0.type == .goal && $0.targetAmount == nil }
        guard !legacyGoals.isEmpty else { return }

        for goal in legacyGoals {
            goal.type = .reserve
            goal.updatedAt = .now
        }
        try? modelContext.save()
    }

    private func archive(_ goal: SavingsGoal) {
        goal.isArchived = true
        goal.updatedAt = .now
        do { try modelContext.save() }
        catch { saveErrorMessage = error.localizedDescription }
        goalToArchive = nil
    }

    private func delete(_ goal: SavingsGoal) {
        modelContext.delete(goal)
        do { try modelContext.save() }
        catch { saveErrorMessage = error.localizedDescription }
        goalToDelete = nil
    }
}

private struct SavingsManagementView: View {
    let goals: [SavingsGoal]
    let archivedGoals: [SavingsGoal]
    let budgets: [Budget]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var editingGoal: SavingsGoal?
    @State private var editorType: SavingsGoalType = .goal
    @State private var showingEditor = false
    @State private var showingArchived = false

    var body: some View {
        NavigationStack {
            List {
                Section("Aktiv") {
                    ForEach(goals) { goal in
                        Button {
                            editingGoal = goal
                            editorType = goal.type
                            showingEditor = true
                        } label: {
                            HStack {
                                Text(goal.name)
                                Spacer()
                                Text(goal.type.title)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .onMove { source, destination in
                        var reordered = goals
                        reordered.move(fromOffsets: source, toOffset: destination)
                        for (index, goal) in reordered.enumerated() { goal.sortOrder = index }
                        try? modelContext.save()
                    }
                }

                Section {
                    Button("Archiv öffnen") { showingArchived = true }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Verwalten")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sheet(isPresented: $showingEditor) {
                if editorType == .goal {
                    SavingsGoalEditorView(goal: editingGoal, budgets: budgets, type: .goal, group: editingGoal?.group)
                } else {
                    FreeReserveEditorView(reserve: editingGoal, budgets: budgets, group: editingGoal?.group)
                }
            }
            .sheet(isPresented: $showingArchived) {
                ArchivedSavingsView(goals: archivedGoals)
            }
        }
    }
}

private struct ArchivedSavingsView: View {
    let goals: [SavingsGoal]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            List(goals) { goal in
                HStack {
                    Text(goal.name)
                    Spacer()
                    Button("Wiederherstellen") {
                        goal.isArchived = false
                        try? modelContext.save()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .navigationTitle("Archiv")
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
}

private struct SavingsGoalDetailView: View {
    let goal: SavingsGoal
    let currencyCode: String
    let onEdit: () -> Void
    let onContribute: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var savedAmount: Decimal {
        goal.savedAmount
    }

    private var contributions: [SavingsContribution] {
        (goal.contributions ?? []).sorted { $0.date > $1.date }
    }

    private var progress: Double {
        guard let target = goal.targetAmount, target > 0 else { return 0 }
        return min(max(NSDecimalNumber(decimal: savedAmount / target).doubleValue, 0), 1)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Übersicht") {
                    LabeledContent("Gespart") {
                        Text(savedAmount, format: .currency(code: currencyCode))
                            .font(.headline)
                    }

                    if let target = goal.targetAmount, target > 0 {
                        LabeledContent("Zielbetrag") {
                            Text(target, format: .currency(code: currencyCode))
                        }
                        LabeledContent("Verbleibend") {
                            Text(max(target - savedAmount, .zero), format: .currency(code: currencyCode))
                        }
                        ProgressView(value: progress)
                            .tint(progress >= 1 ? .green : .accentColor)
                    } else {
                        Text("Freie Rücklage ohne festen Zielbetrag")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Einzahlungen") {
                    if contributions.isEmpty {
                        ContentUnavailableView(
                            "Noch keine Einzahlungen",
                            systemImage: "tray",
                            description: Text("Füge die erste Einzahlung für dieses \(goal.type == .goal ? "Sparziel" : "Rücklage") hinzu.")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(contributions, id: \.persistentModelID) { contribution in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(contribution.date, format: .dateTime.day().month().year())
                                        .font(.headline)
                                    Text(contribution.automatic ? "Automatische Einzahlung" : "Manuelle Einzahlung")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !contribution.note.isEmpty {
                                        Text(contribution.note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(contribution.amount, format: .currency(code: currencyCode))
                                    .font(.headline)
                            }
                        }
                    }
                }
            }
            .navigationTitle(goal.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Einzahlen", action: onContribute)
                        Button("Bearbeiten", action: onEdit)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}

private struct SavingsGoalCardView: View {
    let goal: SavingsGoal
    let currencyCode: String
    let asOf: Date
    let contribute: () -> Void

    private var savedAmount: Decimal {
        goal.savedAmount(asOf: asOf)
    }

    private var historicalProgress: Double {
        guard let target = goal.targetAmount, target > 0 else { return 0 }
        return min(max(NSDecimalNumber(decimal: savedAmount / target).doubleValue, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconBadgeView(
                    iconName: goal.iconName,
                    color: Color(hexString: goal.iconColorHex),
                    size: 46
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.name)
                        .font(.headline)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 3) {
                    Text(savedAmount, format: .currency(code: currencyCode))
                        .font(.headline)
                    if let target = goal.targetAmount, target > 0 {
                        Text("von \(target, format: .currency(code: currencyCode))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if goal.type == .goal {
                ProgressView(value: historicalProgress)
                    .tint(historicalProgress >= 1 ? .green : .accentColor)
            }

            HStack {
                if goal.automaticBooking {
                    Label("Automatisch \(goal.frequency.title.lowercased())", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Manuelle Einzahlung", systemImage: "hand.tap")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let budget = goal.budget {
                    Label(budget.name, systemImage: budget.iconName)
                        .font(.caption)
                        .foregroundStyle(Color(hexString: budget.iconColorHex))
                }

                Spacer()

                Button("Einzahlen", action: contribute)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 5)
    }

}

#Preview {
    SavingsView()
        .modelContainer(for: [UserSettings.self, BudgetGroup.self, BudgetGroupMonthlyAllocation.self, Budget.self, Transaction.self, FixedCost.self, SavingsGoal.self, SavingsContribution.self], inMemory: true)
}
