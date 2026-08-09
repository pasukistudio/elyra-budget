import SwiftData
import SwiftUI

private enum SavingsContributionKind: String, CaseIterable, Identifiable {
    case deposit
    case withdrawal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deposit: "Einzahlen"
        case .withdrawal: "Auszahlen"
        }
    }
}

struct SavingsContributionEditorView: View {
    let goal: SavingsGoal
    let budgets: [Budget]

    private var effectiveGroup: BudgetGroup? {
        goal.group ?? selectedBudget?.group
    }

    private var availableBudgets: [Budget] {
        budgets.filter { budget in
            guard let group = goal.group else { return true }
            return budget.group === group
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCurrencyCode) private var currencyCode

    @State private var amount: Decimal?
    @State private var kind: SavingsContributionKind = .deposit
    @State private var date = Date.now
    @State private var note = ""
    @State private var selectedBudget: Budget?
    @State private var saveErrorMessage: String?

    init(goal: SavingsGoal, budgets: [Budget]) {
        self.goal = goal
        self.budgets = budgets
        _amount = State(initialValue: nil)
        _selectedBudget = State(initialValue: goal.budget)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sparziel") {
                    Text(goal.name).font(.headline)
                    Picker("Art", selection: $kind) {
                        ForEach(SavingsContributionKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    FixedCostEditorAmountSection(amount: $amount)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)

                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                    TextField("Notiz (optional)", text: $note, axis: .vertical)
                }

                Section {
                    HStack {
                        Text(kind == .deposit ? "Vom Budget abziehen" : "Auf Budget buchen")
                        Spacer()
                        Menu {
                            Button("Kein Budget") { selectedBudget = nil }
                            ForEach(availableBudgets, id: \.persistentModelID) { budget in
                                Button {
                                    selectedBudget = budget
                                } label: {
                                    Label(budget.name, systemImage: budget.iconName)
                                }
                            }
                        } label: {
                            Text(selectedBudget?.name ?? "Kein Budget")
                                .foregroundStyle(
                                    selectedBudget == nil
                                        ? AnyShapeStyle(.tint)
                                        : AnyShapeStyle(.secondary)
                                )
                        }
                    }
                } footer: {
                    Text(
                        kind == .deposit
                            ? "Die Einzahlung wird als Ausgabe vom ausgewählten Budget erfasst."
                            : "Die Auszahlung wird als Einnahme im ausgewählten Budget erfasst."
                    )
                }
            }
            .navigationTitle("Einzahlen")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled((amount ?? 0) <= 0)
                }
            }
            .saveErrorAlert(message: $saveErrorMessage)
        }
    }

    private func save() {
        guard let amount, amount > 0 else { return }
        let signedAmount = kind == .deposit ? amount : -amount
        guard kind == .deposit || goal.savedAmount + signedAmount >= 0 else {
            saveErrorMessage = "Die Auszahlung darf den aktuellen Sparstand nicht überschreiten."
            return
        }
        guard BudgetGroupRelationshipValidator.isValid(budget: selectedBudget, in: effectiveGroup) else {
            saveErrorMessage = "Die Zuordnung gehört zu einem anderen Budgetbereich."
            return
        }

        if goal.group == nil {
            goal.group = effectiveGroup
        }

        let contribution = SavingsContribution(
            amount: signedAmount,
            date: date,
            note: note,
            goal: goal
        )
        modelContext.insert(contribution)

        let transaction = Transaction(
            title: goal.name,
            amount: amount,
            date: date,
            note: note.isEmpty ? goal.note : note,
            type: kind == .deposit ? .expense : .income,
            budget: selectedBudget,
            group: effectiveGroup
        )
        transaction.savingsGoalID = goal.id
        modelContext.insert(transaction)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}
