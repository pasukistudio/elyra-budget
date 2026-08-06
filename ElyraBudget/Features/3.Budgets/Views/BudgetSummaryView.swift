import SwiftUI

struct BudgetSummaryView: View {
    let budget: Budget
    let budgetColor: Color
    let currencyCode: String
    let expenseAmount: Decimal
    let refundAmount: Decimal
    let occupiedAmount: Decimal
    let remainingAmount: Decimal
    let visualProgress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            header
            HStack(alignment: .top, spacing: 16) {
                value(title: "Variable Ausgaben", amount: expenseAmount, alignment: .leading, color: .primary)
                Spacer()
                value(title: "Rückerstattungen", amount: refundAmount, alignment: .trailing, color: refundAmount > 0 ? .green : .primary)
            }
            Divider()
            HStack(alignment: .top, spacing: 16) {
                value(title: "Gesamt belegt", amount: occupiedAmount, alignment: .leading, color: occupiedAmount < 0 ? .green : .primary, prominent: true)
                Spacer()
                if budget.limit > 0 {
                    value(title: "Verbleibend", amount: remainingAmount, alignment: .trailing, color: remainingAmount < 0 ? .red : budgetColor, prominent: true)
                }
            }
            if budget.limit > 0 {
                VStack(spacing: 7) {
                    ProgressView(value: visualProgress)
                        .tint(remainingAmount < 0 ? .red : budgetColor)
                    HStack {
                        Text("Limit")
                        Spacer()
                        Text(budget.limit, format: .currency(code: currencyCode))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(budgetColor.opacity(0.14))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: budget.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(budgetColor)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(budget.name).font(.title3.bold()).lineLimit(1)
                Text("Budgetübersicht").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func value(title: String, amount: Decimal, alignment: HorizontalAlignment, color: Color, prominent: Bool = false) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(amount, format: .currency(code: currencyCode))
                .font(prominent ? .title3.bold() : .headline)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
