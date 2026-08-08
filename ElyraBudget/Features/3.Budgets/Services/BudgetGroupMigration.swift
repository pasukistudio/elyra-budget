import Foundation
import SwiftData

enum BudgetGroupMigration {
    @discardableResult
    static func ensureDefaultGroupAndMigrate(
        in modelContext: ModelContext
    ) throws -> BudgetGroup {
        let groups = try modelContext.fetch(FetchDescriptor<BudgetGroup>())
        let group = groups.first(where: isPersonalGroup)
            ?? groups.first(where: { !$0.isArchived })
            ?? groups.first
            ?? BudgetGroup(
                name: "Persönlich",
                iconName: "person.fill",
                iconColorHex: ColorPreset.blue.hex,
                sortOrder: 0
            )

        if groups.isEmpty {
            modelContext.insert(group)
        }

        var didChange = false
        let budgets = try modelContext.fetch(FetchDescriptor<Budget>())
        let fixedCosts = try modelContext.fetch(FetchDescriptor<FixedCost>())
        let savingsGoals = try modelContext.fetch(FetchDescriptor<SavingsGoal>())
        let transactions = try modelContext.fetch(FetchDescriptor<Transaction>())

        for budget in budgets where budget.group == nil {
            budget.group = group
            didChange = true
        }
        for fixedCost in fixedCosts where fixedCost.group == nil {
            fixedCost.group = fixedCost.budget?.group ?? group
            didChange = true
        }
        for savingsGoal in savingsGoals where savingsGoal.group == nil {
            savingsGoal.group = savingsGoal.budget?.group ?? group
            didChange = true
        }
        for transaction in transactions where transaction.group == nil {
            transaction.group = transaction.budget?.group ?? group
            didChange = true
        }

        if didChange || groups.isEmpty {
            try modelContext.save()
        }

        return group
    }

    private nonisolated static func isPersonalGroup(_ group: BudgetGroup) -> Bool {
        group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare("Persönlich") == .orderedSame
    }
}
