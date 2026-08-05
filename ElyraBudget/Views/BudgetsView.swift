import SwiftUI
import SwiftData

struct BudgetsView: View {
    @Binding var showingBudgetEditor: Bool

    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<Budget> {
            !$0.isArchived
        },
        sort: [
            SortDescriptor(\Budget.sortOrder),
            SortDescriptor(\Budget.createdAt)
        ]
    )
    private var budgets: [Budget]

    var body: some View {
        Group {
            if budgets.isEmpty {
                emptyState
            } else {
                budgetList
            }
        }
    }

    // MARK: - Budgetliste

    private var budgetList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(budgets) { budget in
                    budgetCard(budget)
                }
            }
            .padding()
        }
    }

    // MARK: - Leere Ansicht

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                "Noch keine Budgets",
                systemImage: "chart.pie"
            )
        } description: {
            Text(
                "Erstelle Budgets für Lebensmittel, Wohnen, Mobilität und weitere Bereiche."
            )
        } actions: {
            Button("Budget erstellen") {
                showingBudgetEditor = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Budgetkarte

    private func budgetCard(
        _ budget: Budget
    ) -> some View {
        let spent: Decimal = 0

        let progress = progressValue(
            spent: spent,
            limit: budget.limit
        )

        return VStack(alignment: .leading, spacing: 12) {
            budgetHeader(budget)

            budgetValues(
                budget: budget,
                spent: spent
            )

            if budget.limit > 0 {
                ProgressView(value: progress)
                    .tint(
                        Color(
                            hexString: budget.iconColorHex
                        )
                    )
            }
        }
        .padding(16)
        .background(
            .background,
            in: RoundedRectangle(cornerRadius: 18)
        )
    }

    // MARK: - Kartenkopf

    private func budgetHeader(
        _ budget: Budget
    ) -> some View {
        HStack(spacing: 12) {
            budgetIcon(budget)

            Text(budget.name)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Budgetwerte

    private func budgetValues(
        budget: Budget,
        spent: Decimal
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ausgaben")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(
                    spent,
                    format: .currency(code: currencyCode)
                )
                .font(.title3.bold())
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Limit")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if budget.limit > 0 {
                    Text(
                        budget.limit,
                        format: .currency(code: currencyCode)
                    )
                    .font(.headline)
                } else {
                    Text("Kein Limit")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Budget-Icon

    private func budgetIcon(
        _ budget: Budget
    ) -> some View {
        let color = Color(
            hexString: budget.iconColorHex
        )

        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.15))
                .frame(width: 46, height: 46)

            Image(systemName: budget.iconName)
                .font(
                    .system(
                        size: 18,
                        weight: .semibold
                    )
                )
                .foregroundStyle(color)
        }
    }

    // MARK: - Fortschritt

    private func progressValue(
        spent: Decimal,
        limit: Decimal
    ) -> Double {
        guard limit > 0 else {
            return 0
        }

        let spentNumber = NSDecimalNumber(
            decimal: spent
        ).doubleValue

        let limitNumber = NSDecimalNumber(
            decimal: limit
        ).doubleValue

        return min(
            max(spentNumber / limitNumber, 0),
            1
        )
    }

    // MARK: - Währung

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "EUR"
    }

    // MARK: - Löschen

    private func deleteBudget(
        _ budget: Budget
    ) {
        modelContext.delete(budget)

        do {
            try modelContext.save()
        } catch {
            print(
                "Budget konnte nicht gelöscht werden: \(error)"
            )
        }
    }
}
