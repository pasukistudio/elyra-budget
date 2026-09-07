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
                    contributionDetailsCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    HStack {
                        Text("Vom Budget abziehen")
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
                        "Die Buchung wird als Ausgabe vom ausgewählten Budget erfasst."
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

    private var contributionDetailsCard: some View {
        VStack(spacing: 0) {
            Picker("Art", selection: $kind) {
                ForEach(SavingsContributionKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 17)
            .padding(.vertical, 15)

            Divider()
                .padding(.horizontal, 17)

            Text(goal.name)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 17)
                .padding(.vertical, 16)

            Divider()
                .padding(.horizontal, 17)

            FixedCostEditorAmountSection(amount: $amount)

            Divider()
                .padding(.horizontal, 17)

            DatePicker("Datum", selection: $date, displayedComponents: .date)
                .padding(.horizontal, 17)
                .padding(.vertical, 4)

            Divider()
                .padding(.horizontal, 17)

            TextField("Notiz (optional)", text: $note, axis: .vertical)
                .padding(.horizontal, 17)
                .padding(.vertical, 12)
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
    }

    private var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color.secondary.opacity(0.08)
        #endif
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

        let transaction = Transaction(
            title: goal.name,
            amount: amount,
            date: date,
            note: note.isEmpty ? goal.note : note,
            type: .expense,
            budget: selectedBudget,
            group: effectiveGroup
        )
        transaction.savingsGoalID = goal.id
        transaction.savingsContributionID = contribution.id
        contribution.transactionID = transaction.id
        modelContext.insert(contribution)
        modelContext.insert(transaction)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}
