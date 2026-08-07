import SwiftUI

struct TransactionEditorDetailsSection: View {
    @Binding var title: String
    @Binding var date: Date
    @Binding var selectedBudget: Budget?
    @Binding var showingBudgetMenu: Bool
    let footerText: String
    let cardBackground: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TransactionEditorSectionHeader(title: "Details")

            VStack(spacing: 0) {
                TextField("Beschreibung", text: $title)
                    .padding(.horizontal, 17)
                    .frame(minHeight: 56)

                Divider().padding(.horizontal, 17)

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showingBudgetMenu.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text("Budget")
                        Spacer(minLength: 8)
                        selectedBudgetValue
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(showingBudgetMenu ? Color.accentColor : Color.secondary.opacity(0.55))
                    }
                    .padding(.horizontal, 17)
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider().padding(.horizontal, 17)

                HStack(spacing: 12) {
                    Text("Datum")
                    Spacer()
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }
                .padding(.horizontal, 17)
                .frame(minHeight: 56)
            }
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))

            Text(footerText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var selectedBudgetValue: some View {
        if let selectedBudget {
            HStack(spacing: 7) {
                Image(systemName: selectedBudget.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hexString: selectedBudget.iconColorHex))
                Text(selectedBudget.name)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            Text("Kein Budget")
                .foregroundStyle(.tint)
                .lineLimit(1)
        }
    }
}
