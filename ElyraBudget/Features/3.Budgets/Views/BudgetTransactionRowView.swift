import SwiftUI

struct BudgetTransactionRowView: View {
    let transaction: Transaction
    let budgetColor: Color
    let currencyCode: String

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(budgetColor.opacity(0.14))
                    .frame(width: 46, height: 46)
                Image(systemName: transaction.budget?.iconName ?? "cart.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(budgetColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.title).font(.headline).lineLimit(1)
                Text(typeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text(transaction.signedAmount, format: .currency(code: currencyCode))
                    .font(.headline)
                    .foregroundStyle(amountColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(transaction.date, format: .dateTime.day().month(.wide).year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 17)
        .frame(minHeight: 76)
        .contentShape(Rectangle())
    }

    private var typeText: String {
        switch transaction.type {
        case .expense: "Ausgabe"
        case .income: "Einnahme"
        case .refund: "Rückerstattung"
        }
    }

    private var amountColor: Color {
        switch transaction.type {
        case .expense: .primary
        case .income: .green
        case .refund: .blue
        }
    }
}
