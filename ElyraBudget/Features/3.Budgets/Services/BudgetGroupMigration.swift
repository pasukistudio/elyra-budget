import Foundation
import SwiftData

enum BudgetGroupMigration {
    static func migrateBudgetStatusThresholds(
        in modelContext: ModelContext
    ) throws {
        let groups = try modelContext.fetch(FetchDescriptor<BudgetGroup>())
        guard !groups.isEmpty,
              let profile = try modelContext.fetch(FetchDescriptor<UserSettings>()).first,
              profile.greenBudgetThreshold != 70 || profile.orangeBudgetThreshold != 100
        else {
            return
        }

        var didChange = false
        for group in groups where group.greenBudgetThreshold == 70 && group.orangeBudgetThreshold == 100 {
            group.greenBudgetThreshold = profile.greenBudgetThreshold
            group.orangeBudgetThreshold = max(
                profile.orangeBudgetThreshold,
                profile.greenBudgetThreshold + 1
            )
            group.updatedAt = .now
            didChange = true
        }

        if didChange {
            try modelContext.save()
        }
    }

    static func ensureAtLeastOneActiveGroup(
        in modelContext: ModelContext
    ) throws {
        let groups = try modelContext.fetch(FetchDescriptor<BudgetGroup>())
        guard !groups.isEmpty, groups.allSatisfy(\.isArchived),
              let group = groups.first else {
            return
        }

        group.isArchived = false
        group.updatedAt = .now
        try modelContext.save()
    }

    @discardableResult
    static func ensureDefaultGroupAndMigrate(
        in modelContext: ModelContext
    ) throws -> BudgetGroup {
        let groups = try modelContext.fetch(FetchDescriptor<BudgetGroup>())
        let activeGroups = groups.filter { !$0.isArchived }
        let group = activeGroups.first(where: isPersonalGroup)
            ?? activeGroups.first
            ?? groups.first(where: isPersonalGroup)
            ?? groups.first
            ?? BudgetGroup(
                name: "Persönlich",
                iconName: "person.fill",
                iconColorHex: ColorPreset.blue.hex,
                sortOrder: 0
            )

        var didChange = false
        if group.isArchived {
            group.isArchived = false
            group.updatedAt = .now
            didChange = true
        }

        if groups.isEmpty {
            modelContext.insert(group)
            didChange = true
        }

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

        if didChange {
            try modelContext.save()
        }

        return group
    }

    private nonisolated static func isPersonalGroup(_ group: BudgetGroup) -> Bool {
        group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare("Persönlich") == .orderedSame
    }
}
