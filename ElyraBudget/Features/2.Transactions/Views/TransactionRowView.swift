import SwiftUI

struct TransactionRowView: View {
    let transaction: Transaction
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            transactionIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.title)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(transaction.date, format: .dateTime.hour().minute())
                    if let budget = transaction.budget {
                        Text("•")
                        HStack(spacing: 4) {
                            Image(systemName: budget.iconName)
                            Text(budget.name)
                        }
                        .foregroundStyle(Color(hexString: budget.iconColorHex))
                        .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
            Text(transaction.signedAmount, format: .currency(code: currencyCode))
                .font(.headline)
                .foregroundStyle(amountColor)
        }
        .padding(.vertical, 4)
    }

    private var transactionIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(amountColor.opacity(0.14))
                .frame(width: 44, height: 44)
            Image(systemName: transaction.type.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(amountColor)
        }
    }

    private var amountColor: Color {
        switch transaction.type {
        case .expense: .red
        case .income: .green
        case .refund: .blue
        }
    }
}
