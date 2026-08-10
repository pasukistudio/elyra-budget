import Foundation
import SwiftData

@Model
final class Budget {
    // MARK: - Grunddaten

    var id: UUID = UUID()

    var name: String = ""

    // MARK: - Darstellung

    var iconName: String = "cart.fill"
    var iconColorHex: String = "#FF9500"

    // MARK: - Budgeteinstellungen

    /// `0` bedeutet: Das Budget besitzt kein Limit.
    var limit: Decimal = 0

    var includesFixedCosts: Bool = true

    /// Optional until budget groups are introduced for existing data.
    var group: BudgetGroup?

    // MARK: - Buchungen

    @Relationship(
        deleteRule: .nullify,
        inverse: \Transaction.budget
    )
    var transactions: [Transaction]? = []

    @Relationship(
        deleteRule: .nullify,
        inverse: \FixedCost.budget
    )
    var fixedCosts: [FixedCost]? = []

    @Relationship(
        deleteRule: .nullify,
        inverse: \SavingsGoal.budget
    )
    var savingsGoals: [SavingsGoal]? = []

    // MARK: - Organisation

    var sortOrder: Int = 0
    var isArchived: Bool = false

    // MARK: - Zeitstempel

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: - Initialisierung

    init(
        name: String = "",
        iconName: String = "cart.fill",
        iconColorHex: String = "#FF9500",
        limit: Decimal = 0,
        includesFixedCosts: Bool = true,
        group: BudgetGroup? = nil,
        sortOrder: Int = 0,
        isArchived: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.iconName = iconName
        self.iconColorHex = iconColorHex
        self.limit = limit
        self.includesFixedCosts = includesFixedCosts
        self.group = group
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: - Berechnete Buchungen

    var sortedTransactions: [Transaction] {
        (transactions ?? [])
            .sorted {
                $0.date > $1.date
            }
    }

    // MARK: - Berechnete Budgetwerte

    var spentAmount: Decimal {
        (transactions ?? []).reduce(
            Decimal.zero
        ) { result, transaction in
            result + transaction.budgetImpact
        }
    }

    func transactions(in month: Date, calendar: Calendar = .current) -> [Transaction] {
        return (transactions ?? []).filter {
            $0.date.isInSameMonth(as: month, calendar: calendar)
        }
    }

    func spentAmount(in month: Date, calendar: Calendar = .current) -> Decimal {
        transactions(in: month, calendar: calendar).reduce(.zero) {
            $0 + $1.budgetImpact
        }
    }

    var remainingAmount: Decimal? {
        guard limit > 0 else {
            return nil
        }

        return limit - spentAmount
    }

    var progress: Double {
        guard limit > 0 else {
            return 0
        }

        let spentNumber = NSDecimalNumber(
            decimal: spentAmount
        ).doubleValue

        let limitNumber = NSDecimalNumber(
            decimal: limit
        ).doubleValue

        guard limitNumber > 0 else {
            return 0
        }

        return spentNumber / limitNumber
    }

    var visualProgress: Double {
        min(
            max(progress, 0),
            1
        )
    }

    var progressPercentage: Double {
        progress * 100
    }

    var isOverBudget: Bool {
        guard limit > 0 else {
            return false
        }

        return spentAmount > limit
    }

    var exceededAmount: Decimal {
        guard isOverBudget else {
            return 0
        }

        return spentAmount - limit
    }
}
