import SwiftUI

struct BudgetGroupContextRow: View {
    let group: BudgetGroup?

    var body: some View {
        HStack(spacing: 12) {
            Label("Budgetbereich", systemImage: "person.2")
            Spacer()

            if let group {
                HStack(spacing: 6) {
                    Image(systemName: group.iconName)
                        .foregroundStyle(Color(hexString: group.iconColorHex))
                    Text(group.name)
                }
                .foregroundStyle(.secondary)
            } else {
                Text("Kein Bereich")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            group.map { "Budgetbereich \($0.name)" } ?? "Kein Budgetbereich"
        )
    }
}
