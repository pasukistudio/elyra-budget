import SwiftData
import SwiftUI

struct SavingsContributionEditorView: View {
    let goal: SavingsGoal
    let budgets: [Budget]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCurrencyCode) private var currencyCode

    @State private var amount: Decimal?
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
                    FixedCostEditorAmountSection(amount: $amount)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    HStack {
                        Text("Vom Budget abziehen")
                        Spacer()
                        Menu {
                            Button("Kein Budget") { selectedBudget = nil }
                            ForEach(budgets, id: \.persistentModelID) { budget in
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
                    Text("Die Einzahlung wird als Ausgabe vom ausgewählten Budget erfasst.")
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

        let contribution = SavingsContribution(amount: amount, goal: goal)
        modelContext.insert(contribution)

        let transaction = Transaction(
            title: goal.name,
            amount: amount,
            note: goal.note,
            type: .expense,
            budget: selectedBudget,
            group: goal.group ?? selectedBudget?.group
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
