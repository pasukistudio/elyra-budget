import SwiftUI

/// Uses the same amount field presentation and locale handling as transaction creation.
struct FixedCostEditorAmountSection: View {
    @Environment(\.appCurrencyCode) private var currencyCode
    @Environment(\.locale) private var locale

    @Binding var amount: Decimal?

    @State private var amountText: String

    init(amount: Binding<Decimal?>) {
        _amount = amount
        _amountText = State(initialValue: amount.wrappedValue.map {
            Self.formattedAmount($0, separator: Locale.current.decimalSeparator ?? ".")
        } ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 4) {
                Spacer(minLength: 0)

                CurrencyAmountTextField(
                    text: $amountText,
                    fontSize: amountFontSize,
                    decimalSeparator: decimalSeparator
                )
                .frame(width: amountInputWidth)
                .onChange(of: amountText) { _, newValue in
                    amount = Decimal(
                        string: newValue.replacingOccurrences(
                            of: decimalSeparator,
                            with: "."
                        )
                    )
                }
                .onChange(of: amount) { _, newValue in
                    guard !isEditingAmount else { return }
                    amountText = newValue.map {
                        Self.formattedAmount($0, separator: decimalSeparator)
                    } ?? ""
                }
                .padding(.vertical, 15)

                Text(currencySymbol)
                    .font(.system(size: amountFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        amountText.isEmpty
                            ? Color.secondary.opacity(0.65)
                            : Color.primary
                    )

                Spacer(minLength: 0)
            }
            .frame(minHeight: 84)
            .contentShape(Rectangle())
        }
    }

    private var currencySymbol: String {
        AppCurrency(rawValue: currencyCode)?.symbol ?? currencyCode
    }

    private var decimalSeparator: String {
        locale.decimalSeparator ?? "."
    }

    private var amountDigitCount: Int {
        guard !amountText.isEmpty else { return 4 }
        return amountText.filter(\.isNumber).count
    }

    private var amountFontSize: CGFloat {
        max(22, min(36, 36 - CGFloat(max(0, amountDigitCount - 5)) * 4))
    }

    private var amountInputWidth: CGFloat {
        let characterWidth = amountFontSize * 0.58
        let preferredWidth = CGFloat(max(amountText.count, 1)) * characterWidth + 18
        return min(300, max(82, preferredWidth))
    }

    private static func formattedAmount(_ amount: Decimal, separator: String) -> String {
        let rawValue = NSDecimalNumber(decimal: amount).stringValue
        let parts = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        let integer = parts.first.map(String.init) ?? "0"
        let decimals = String(parts.dropFirst().first ?? "")
            .padding(toLength: 2, withPad: "0", startingAt: 0)
        return integer + separator + String(decimals.prefix(2))
    }

    private var isEditingAmount: Bool {
        let normalizedText = amountText.replacingOccurrences(of: decimalSeparator, with: ".")
        return normalizedText != (amount.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
    }
}
