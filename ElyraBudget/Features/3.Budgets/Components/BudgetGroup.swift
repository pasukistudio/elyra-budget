import Foundation
import SwiftData

/// A top-level financial area such as a personal or shared account.
@Model
final class BudgetGroup {
    var id: UUID = UUID()
    var name: String = ""
    var iconName: String = "person.2.fill"
    var iconColorHex: String = "#007AFF"
    var sortOrder: Int = 0
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(
        deleteRule: .nullify,
        inverse: \Budget.group
    )
    var budgets: [Budget]? = []

    @Relationship(
        deleteRule: .nullify,
        inverse: \FixedCost.group
    )
    var fixedCosts: [FixedCost]? = []

    @Relationship(
        deleteRule: .nullify,
        inverse: \SavingsGoal.group
    )
    var savingsGoals: [SavingsGoal]? = []

    @Relationship(
        deleteRule: .nullify,
        inverse: \Transaction.group
    )
    var transactions: [Transaction]? = []

    init(
        name: String = "",
        iconName: String = "person.2.fill",
        iconColorHex: String = "#007AFF",
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.iconName = iconName
        self.iconColorHex = iconColorHex
        self.sortOrder = sortOrder
        self.createdAt = .now
        self.updatedAt = .now
    }
}
