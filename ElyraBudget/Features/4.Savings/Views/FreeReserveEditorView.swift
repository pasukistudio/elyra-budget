import SwiftUI

struct FreeReserveEditorView: View {
    let reserve: SavingsGoal?
    let budgets: [Budget]
    let group: BudgetGroup?

    init(
        reserve: SavingsGoal?,
        budgets: [Budget],
        group: BudgetGroup? = nil
    ) {
        self.reserve = reserve
        self.budgets = budgets
        self.group = group
    }

    var body: some View {
        SavingsGoalEditorView(
            goal: reserve,
            budgets: budgets,
            type: .reserve,
            group: group
        )
    }
}
