import SwiftUI

struct BudgetCardView: View {
    let budget: Budget
    let currencyCode: String
    let selectedMonth: Date
    let showsGroupContext: Bool

    init(
        budget: Budget,
        currencyCode: String,
        selectedMonth: Date,
        showsGroupContext: Bool = false
    ) {
        self.budget = budget
        self.currencyCode = currencyCode
        self.selectedMonth = selectedMonth
        self.showsGroupContext = showsGroupContext
    }

    private var spentAmount: Decimal {
        budget.spentAmount(in: selectedMonth)
    }

    private var progress: Double {
        guard budget.limit > 0 else { return 0 }
        return min(max(NSDecimalNumber(decimal: spentAmount).doubleValue / NSDecimalNumber(decimal: budget.limit).doubleValue, 0), 1)
    }

    private var remainingAmount: Decimal? {
        guard budget.limit > 0 else { return nil }
        return budget.limit - spentAmount
    }

    private var accentColor: Color {
        Color(hexString: budget.iconColorHex)
    }

    private var cardBackground: Color {
        #if os(iOS)
            Color(uiColor: .secondarySystemGroupedBackground)
        #else
            Color(nsColor: .controlBackgroundColor)
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                BudgetIconView(budget: budget)

                VStack(alignment: .leading, spacing: 2) {
                    Text(budget.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if showsGroupContext, let group = budget.group {
                        Text(group.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(spentAmount, format: .currency(code: currencyCode))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if budget.limit > 0 {
                        Text("von \(budget.limit, format: .currency(code: currencyCode))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Kein Limit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if budget.limit > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: progress)
                        .tint(accentColor)

                    HStack {
                        remainingLabel

                        Spacer()

                        Text(progressLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.primary.opacity(0.07), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var remainingLabel: some View {
        if let remainingAmount {
            HStack(spacing: 4) {
                Text(remainingAmount >= 0 ? "Verfügbar" : "Über Limit")
                Text(abs(remainingAmount), format: .currency(code: currencyCode))
            }
            .foregroundStyle(remainingAmount >= 0 ? Color.secondary : Color.red)
        } else {
            Text("Kein Limit")
                .foregroundStyle(.secondary)
        }
    }

    private var progressLabel: String {
        let percentage = Int((progress * 100).rounded())
        return "\(percentage) % verwendet"
    }

}
