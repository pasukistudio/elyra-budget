import SwiftData
import SwiftUI

struct BudgetSelectionView: View {
    let budgets: [Budget]

    @Binding var selectedBudget: Budget?

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        NavigationStack {
            List {
                noBudgetRow

                ForEach(budgets) { budget in
                    budgetRow(budget)
                }
            }
            .navigationTitle("Budget auswählen")

            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif

            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Kein Budget

    private var noBudgetRow: some View {
        Button {
            selectedBudget = nil
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: 9,
                        style: .continuous
                    )
                    .fill(
                        Color.secondary.opacity(0.12)
                    )
                    .frame(
                        width: 38,
                        height: 38
                    )

                    Image(
                        systemName: "xmark"
                    )
                    .font(
                        .system(
                            size: 14,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.secondary)
                }

                Text("Kein Budget")
                    .foregroundStyle(.primary)

                Spacer()

                if selectedBudget == nil {
                    Image(
                        systemName: "checkmark"
                    )
                    .font(.body.bold())
                    .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Budgetzeile

    private func budgetRow(
        _ budget: Budget
    ) -> some View {
        Button {
            selectedBudget = budget
            dismiss()
        } label: {
            HStack(spacing: 12) {
                BudgetIconView(budget: budget, size: 38)

                Text(budget.name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                if selectedBudget?.persistentModelID ==
                    budget.persistentModelID {
                    Image(
                        systemName: "checkmark"
                    )
                    .font(.body.bold())
                    .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

}
