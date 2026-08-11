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

                if transaction.receiptFilename != nil {
                    Label("Beleg", systemImage: "paperclip")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let originalAmount = transaction.roundUpOriginalAmount {
                    HStack(spacing: 2) {
                        Text("Original")
                        Text(originalAmount, format: .currency(code: currencyCode))
                        Text("·")
                        Text(transaction.amount - originalAmount, format: .currency(code: currencyCode))
                        Text("gespart")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                if let budget = transaction.budget {
                    Text(budget.name)
                    .font(.caption)
                    .foregroundStyle(Color(hexString: budget.iconColorHex))
                    .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(transaction.signedAmount, format: .currency(code: currencyCode))
                    .font(.headline)
                    .foregroundStyle(amountColor)

                Text(transaction.date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var transactionIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(transactionIconColor.opacity(0.14))
                .frame(width: 44, height: 44)
            Image(systemName: transactionIconName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(transactionIconColor)
        }
    }

    private var transactionIconName: String {
        transaction.budget?.iconName ?? transaction.type.systemImage
    }

    private var transactionIconColor: Color {
        if let budget = transaction.budget {
            return Color(hexString: budget.iconColorHex)
        }

        return amountColor
    }

    private var amountColor: Color {
        switch transaction.type {
        case .expense: .red
        case .income: .green
        case .refund: .blue
        }
    }
}
