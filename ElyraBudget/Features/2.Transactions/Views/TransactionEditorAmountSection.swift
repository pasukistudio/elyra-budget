import SwiftUI

struct TransactionEditorAmountSection: View {
    @Binding var amount: Decimal?
    @Binding var selectedType: TransactionType
    let cardBackground: Color

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

            ZStack {
                if amount == nil {
                    Text("0,00 €")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }

                TextField("", value: $amount, format: .number.precision(.fractionLength(0 ... 2)))
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 15)
                #if os(iOS)
                    .keyboardType(.decimalPad)
                #endif
            }
            .frame(minHeight: 84)
            .contentShape(Rectangle())
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
    }
}
