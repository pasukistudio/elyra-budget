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

    /// The fallback monthly allowance used when a month has no override.
    /// A value of `0` means that no group allowance has been configured yet.
    var standardMonthlyBudget: Decimal = 0
    /// Rounds expense transactions up to the next full currency unit.
    var roundUpTransactionsEnabled: Bool = false
    /// Identifies the automatically created reserve that receives round-up differences.
    var roundUpReserveID: UUID?

    @Relationship(
        deleteRule: .cascade,
        inverse: \BudgetGroupMonthlyAllocation.group
    )
    var monthlyAllocations: [BudgetGroupMonthlyAllocation]? = []

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
        sortOrder: Int = 0,
        standardMonthlyBudget: Decimal = 0
    ) {
        self.id = UUID()
        self.name = name
        self.iconName = iconName
        self.iconColorHex = iconColorHex
        self.sortOrder = sortOrder
        self.standardMonthlyBudget = standardMonthlyBudget
        self.roundUpTransactionsEnabled = false
        self.roundUpReserveID = nil
        self.createdAt = .now
        self.updatedAt = .now
    }

    func monthlyBudget(for month: Date, calendar: Calendar = .current) -> Decimal {
        let monthStart = calendar.dateInterval(of: .month, for: month)?.start ?? month
        if let override = (monthlyAllocations ?? []).first(where: {
            calendar.isDate($0.monthStart, equalTo: monthStart, toGranularity: .month)
        }) {
            return override.amount
        }
        return standardMonthlyBudget
    }

    func monthlyAllocation(for month: Date, calendar: Calendar = .current) -> BudgetGroupMonthlyAllocation? {
        let monthStart = calendar.dateInterval(of: .month, for: month)?.start ?? month
        return (monthlyAllocations ?? []).first {
            calendar.isDate($0.monthStart, equalTo: monthStart, toGranularity: .month)
        }
    }
}

/// A month-specific override for a budget group's monthly allowance.
@Model
final class BudgetGroupMonthlyAllocation {
    var monthStart: Date = Date()
    var amount: Decimal = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var group: BudgetGroup?

    init(monthStart: Date, amount: Decimal, group: BudgetGroup? = nil) {
        self.monthStart = Calendar.current.dateInterval(of: .month, for: monthStart)?.start ?? monthStart
        self.amount = amount
        self.group = group
        self.createdAt = .now
        self.updatedAt = .now
    }
}
