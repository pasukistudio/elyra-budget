import SwiftData
import SwiftUI

struct SavingsView: View {
    @Binding private var addRequested: Bool
    @Binding private var reserveRequested: Bool
    @Binding private var managementRequested: Bool
    @Binding private var archiveRequested: Bool

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
    @State private var goalToDelete: SavingsGoal?
    @State private var saveErrorMessage: String?

    init(
        addRequested: Binding<Bool> = .constant(false),
        reserveRequested: Binding<Bool> = .constant(false),
        managementRequested: Binding<Bool> = .constant(false),
        archiveRequested: Binding<Bool> = .constant(false)
    ) {
        _addRequested = addRequested
        _reserveRequested = reserveRequested
        _managementRequested = managementRequested
        _archiveRequested = archiveRequested
    }

    var body: some View {
        Group {
            if goals.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .sheet(isPresented: $showingEditor) {
            if editorType == .goal {
                SavingsGoalEditorView(goal: editingGoal, budgets: budgets, type: .goal)
            } else {
                FreeReserveEditorView(reserve: editingGoal, budgets: budgets)
            }
        }
        .sheet(isPresented: $showingManagement) {
            SavingsManagementView(goals: goals, archivedGoals: archivedGoals, budgets: budgets)
        }
        .sheet(isPresented: $showingArchived) {
            ArchivedSavingsView(goals: archivedGoals)
        }
        .sheet(item: $contributingGoal) { goal in
            SavingsContributionEditorView(goal: goal, budgets: budgets)
        }
        .alert(
            "In den Archiv verschieben?",
            isPresented: deleteConfirmationIsPresented,
            presenting: goalToDelete
        ) { goal in
            Button("Archivieren") { archive(goal) }
            Button("Abbrechen", role: .cancel) { goalToDelete = nil }
        } message: { goal in
            Text("„\(goal.name)“ bleibt erhalten und kann später im Archiv wiederhergestellt werden.")
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
            let activeGoals = goals.filter { $0.type == .goal }
            let reserves = goals.filter { $0.type == .reserve }

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
            if goals.isEmpty {
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
            contribute: { contributingGoal = goal }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            editingGoal = goal
            editorType = goal.type
            showingEditor = true
        }
        .swipeActions {
            Button {
                goalToDelete = goal
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
                    SavingsGoalEditorView(goal: editingGoal, budgets: budgets, type: .goal)
                } else {
                    FreeReserveEditorView(reserve: editingGoal, budgets: budgets)
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

private struct SavingsGoalCardView: View {
    let goal: SavingsGoal
    let currencyCode: String
    let contribute: () -> Void

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
                    Text(goal.savedAmount, format: .currency(code: currencyCode))
                        .font(.headline)
                    if let target = goal.targetAmount, target > 0 {
                        Text("von \(target, format: .currency(code: currencyCode))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if goal.type == .goal {
                ProgressView(value: goal.visualProgress)
                    .tint(goal.isCompleted ? .green : .accentColor)
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
        .modelContainer(for: [UserSettings.self, Budget.self, Transaction.self, FixedCost.self, SavingsGoal.self, SavingsContribution.self], inMemory: true)
}
