import SwiftUI

struct TransactionEditorAmountSection: View {
    @Environment(\.appCurrencyCode) private var currencyCode
    @Environment(\.locale) private var locale
    @Binding var amount: Decimal?
    @Binding var selectedType: TransactionType
    let cardBackground: Color

    @State private var amountText: String

    init(
        amount: Binding<Decimal?>,
        selectedType: Binding<TransactionType>,
        cardBackground: Color
    ) {
        _amount = amount
        _selectedType = selectedType
        self.cardBackground = cardBackground
        _amountText = State(
            initialValue: amount.wrappedValue.map {
                Self.formattedAmount(
                    $0,
                    separator: Locale.current.decimalSeparator ?? "."
                )
            } ?? ""
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Buchungstyp", selection: $selectedType) {
                ForEach(TransactionType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 15)

            Divider().padding(.horizontal, 16)

            HStack(alignment: .center, spacing: 4) {
                Spacer(minLength: 0)

                CurrencyAmountTextField(
                    text: $amountText,
                    fontSize: amountFontSize,
                    decimalSeparator: decimalSeparator
                )
                    .frame(width: amountInputWidth)
                    .onChange(of: amountText) { _, newValue in
                        let normalized = newValue
                            .replacingOccurrences(of: decimalSeparator, with: ".")
                        amount = Decimal(string: normalized)
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
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
    }

    private var currencySymbol: String {
        AppCurrency(rawValue: currencyCode)?.symbol ?? currencyCode
    }

    private var decimalSeparator: String {
        locale.decimalSeparator ?? "."
    }

    private var amountDigitCount: Int {
        guard !amountText.isEmpty else { return 4 }
        return amountText
            .filter { $0.isNumber }
            .count
    }

    private var amountFontSize: CGFloat {
        max(22, min(36, 36 - CGFloat(max(0, amountDigitCount - 5)) * 4))
    }

    private var amountInputWidth: CGFloat {
        let characterWidth = amountFontSize * 0.58
        let preferredWidth = CGFloat(max(amountText.count, 1)) * characterWidth + 18
        return min(300, max(82, preferredWidth))
    }

    private static func formattedAmount(
        _ amount: Decimal,
        separator: String
    ) -> String {
        let rawValue = NSDecimalNumber(decimal: amount)
            .stringValue
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
