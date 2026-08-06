import SwiftData
import SwiftUI

struct TransactionEditorBudgetMenu: View {
    let budgets: [Budget]
    @Binding var selectedBudget: Budget?
    @Binding var isPresented: Bool

    private let rowHeight: CGFloat = 42

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                row(title: "Kein Budget", icon: nil, color: .secondary, selected: selectedBudget == nil) {
                    select(nil)
                }

                ForEach(budgets, id: \.persistentModelID) { budget in
                    row(
                        title: budget.name,
                        icon: budget.iconName,
                        color: Color(hexString: budget.iconColorHex),
                        selected: selectedBudget?.persistentModelID == budget.persistentModelID
                    ) {
                        select(budget)
                    }
                }
            }
            .padding(.vertical, 7)
        }
        .scrollIndicators(.hidden)
        .frame(width: 250, height: min(CGFloat(budgets.count + 1) * rowHeight + 14, 315))
        .background(.regularMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.primary.opacity(0.1), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 8)
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottomTrailing)))
    }

    private func row(title: String, icon: String?, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(selected ? 1 : 0)
                    .frame(width: 18)

                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(color)
                        .frame(width: 22)
                } else {
                    Color.clear.frame(width: 22, height: 18)
                }

                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func select(_ budget: Budget?) {
        selectedBudget = budget
        withAnimation(.easeInOut(duration: 0.16)) {
            isPresented = false
        }
    }
}
