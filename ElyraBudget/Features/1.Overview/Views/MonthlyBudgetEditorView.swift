import SwiftData
import SwiftUI

struct MonthlyBudgetEditorView: View {
    let selectedGroup: BudgetGroup?
    let selectedDate: Date
    let isMonthlyStartPrompt: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCurrencyCode) private var currencyCode

    @Query(
        filter: #Predicate<BudgetGroup> { !$0.isArchived },
        sort: [SortDescriptor<BudgetGroup>(\.sortOrder)]
    )
    private var budgetGroups: [BudgetGroup]

    @State private var draftAmounts: [UUID: Decimal] = [:]
    @State private var saveErrorMessage: String?

    init(
        selectedGroup: BudgetGroup?,
        selectedDate: Date,
        isMonthlyStartPrompt: Bool = false
    ) {
        self.selectedGroup = selectedGroup
        self.selectedDate = selectedDate
        self.isMonthlyStartPrompt = isMonthlyStartPrompt
    }

    private var editableGroups: [BudgetGroup] {
        if let selectedGroup {
            return [selectedGroup]
        }
        return budgetGroups
    }

    private var monthTitle: String {
        selectedDate.formatted(.dateTime.month(.wide).year())
    }

    var body: some View {
        NavigationStack {
            Form {
                if editableGroups.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "Keine Bereiche vorhanden",
                            systemImage: "square.grid.2x2",
                            description: Text("Lege zuerst einen Budgetbereich an.")
                        )
                    }
                } else if let selectedGroup {
                    Section {
                        standardAmountRow(for: selectedGroup)
                    } header: {
                        Text("Standardbudget")
                    } footer: {
                        Text("Das Standardbudget wird für alle Monate verwendet, für die du keinen eigenen Monatswert festlegst.")
                    }

                    Section {
                        amountRow(for: selectedGroup)
                    } header: {
                        Text("Budget diesen Monat")
                    } footer: {
                        Text("Für \(monthTitle) kannst du das Standardbudget einmalig überschreiben.")
                    }
                } else {
                    Section {
                        ForEach(editableGroups) { group in
                            amountRow(for: group)
                        }
                    } header: {
                        Text("Monatsbudgets für \(monthTitle)")
                    } footer: {
                        Text("Der Wert gilt für diesen Monat. Andere Monate verwenden weiterhin ihren Standardwert.")
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                if isMonthlyStartPrompt {
                    Label(
                        "Ein neuer Monat hat begonnen. Lege jetzt dein Budget für \(monthTitle) fest.",
                        systemImage: "calendar.badge.clock"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(.thinMaterial)
                }
            }
            .navigationTitle(isMonthlyStartPrompt ? "Monatsbudget festlegen" : "Monatsbudget")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Später") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(editableGroups.isEmpty)
                }
            }
            .task {
                loadDraftAmounts()
            }
            .saveErrorAlert(message: $saveErrorMessage)
        }
    }

    private func standardAmountRow(for group: BudgetGroup) -> some View {
        HStack {
            Label {
                Text(group.name)
            } icon: {
                Image(systemName: group.iconName)
                    .foregroundStyle(Color(hexString: group.iconColorHex))
            }

            Spacer()

            Text(group.standardMonthlyBudget, format: .currency(code: currencyCode))
                .foregroundStyle(.secondary)
        }
    }

    private func amountRow(for group: BudgetGroup) -> some View {
        HStack {
            Label {
                Text(group.name)
            } icon: {
                Image(systemName: group.iconName)
                    .foregroundStyle(Color(hexString: group.iconColorHex))
            }

            Spacer()

            TextField(
                "Standard",
                value: amountBinding(for: group),
                format: .number.precision(.fractionLength(0 ... 2))
            )
            .multilineTextAlignment(.trailing)
#if os(iOS)
            .keyboardType(.decimalPad)
#endif
            .frame(maxWidth: 120)

            Text(currencySymbol)
                .foregroundStyle(.secondary)
        }
    }

    private func amountBinding(for group: BudgetGroup) -> Binding<Decimal> {
        Binding(
            get: {
                draftAmounts[group.id] ?? group.monthlyBudget(for: selectedDate)
            },
            set: { draftAmounts[group.id] = $0 }
        )
    }

    private func loadDraftAmounts() {
        var amounts: [UUID: Decimal] = [:]
        for group in editableGroups {
            amounts[group.id] = group.monthlyBudget(for: selectedDate)
        }
        draftAmounts = amounts
    }

    private func save() {
        for group in editableGroups {
            let amount = max(.zero, draftAmounts[group.id] ?? .zero)
            if let allocation = group.monthlyAllocation(for: selectedDate) {
                allocation.amount = amount
                allocation.updatedAt = .now
            } else {
                let allocation = BudgetGroupMonthlyAllocation(
                    monthStart: selectedDate,
                    amount: amount,
                    group: group
                )
                modelContext.insert(allocation)
            }
            group.updatedAt = .now
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveErrorMessage = "Das Monatsbudget konnte nicht gespeichert werden."
        }
    }

    private var currencySymbol: String {
        AppCurrency(rawValue: currencyCode)?.symbol ?? currencyCode
    }
}
