enum BudgetGroupRelationshipValidator {
    static func isValid(budget: Budget?, in group: BudgetGroup?) -> Bool {
        guard let group, let budget else { return true }
        return budget.group === group
    }

    static func isValid(fixedCost: FixedCost?, in group: BudgetGroup?) -> Bool {
        guard let group, let fixedCost else { return true }
        return fixedCost.group === group
    }
}
