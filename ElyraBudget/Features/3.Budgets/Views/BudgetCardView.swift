import SwiftUI

struct BudgetCardView: View {
    let budget: Budget
    let currencyCode: String
    let selectedMonth: Date

    private var spentAmount: Decimal {
        budget.spentAmount(in: selectedMonth)
    }

    private var progress: Double {
        guard budget.limit > 0 else { return 0 }
        return min(max(NSDecimalNumber(decimal: spentAmount).doubleValue / NSDecimalNumber(decimal: budget.limit).doubleValue, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                BudgetIconView(budget: budget)

                Text(budget.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ausgaben")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(spentAmount, format: .currency(code: currencyCode))
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Limit")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if budget.limit > 0 {
                        Text(budget.limit, format: .currency(code: currencyCode))
                            .font(.headline)
                    } else {
                        Text("Kein Limit")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if budget.limit > 0 {
                ProgressView(value: progress)
                    .tint(Color(hexString: budget.iconColorHex))
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

}
