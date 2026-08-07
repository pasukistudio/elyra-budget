import SwiftUI

struct FreeReserveEditorView: View {
    let reserve: SavingsGoal?
    let budgets: [Budget]

    var body: some View {
        SavingsGoalEditorView(
            goal: reserve,
            budgets: budgets,
            type: .reserve
        )
    }
}
