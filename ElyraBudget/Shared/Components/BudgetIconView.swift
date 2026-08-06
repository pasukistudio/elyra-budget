import SwiftUI

struct BudgetIconView: View {
    let budget: Budget
    let size: CGFloat

    init(budget: Budget, size: CGFloat = 46) {
        self.budget = budget
        self.size = size
    }

    var body: some View {
        IconBadgeView(
            iconName: budget.iconName,
            color: Color(hexString: budget.iconColorHex),
            size: size
        )
    }
}
