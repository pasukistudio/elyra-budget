//
//  ElyraBudgetTests.swift
//  ElyraBudgetTests
//
//  Created by Pascal Smigielski on 04.08.26.
//

import Foundation
import SwiftData
import Testing
@testable import ElyraBudget

struct ElyraBudgetTests {

    @Test func budgetGroupUsesMonthlyOverrideBeforeStandardAllowance() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let august = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
        let september = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let group = BudgetGroup(name: "Persönlich", standardMonthlyBudget: 2_000)
        let override = BudgetGroupMonthlyAllocation(monthStart: august, amount: 2_500, group: group)
        group.monthlyAllocations = [override]

        #expect(group.monthlyBudget(for: august, calendar: calendar) == 2_500)
        #expect(group.monthlyBudget(for: september, calendar: calendar) == 2_000)
    }

    @Test func financialItemsCanShareBudgetGroup() {
        let group = BudgetGroup(name: "Gemeinschaftsbudget")
        let budget = Budget(name: "Versicherung", group: group)
        let fixedCost = FixedCost(title: "Hausratversicherung", budget: budget, group: group)
        let savingsGoal = SavingsGoal(name: "Renovierung", budget: budget, group: group)
        let transaction = Transaction(
            title: "Hausratversicherung",
            amount: 25,
            budget: budget,
            group: group
        )

        #expect(budget.group === group)
        #expect(fixedCost.group === group)
        #expect(savingsGoal.group === group)
        #expect(transaction.group === group)
    }

    @Test func budgetGroupRelationshipsRejectCrossGroupAssignments() {
        let personal = BudgetGroup(name: "Persönlich")
        let shared = BudgetGroup(name: "Gemeinsam")
        let budget = Budget(name: "Versicherung", group: shared)
        let fixedCost = FixedCost(title: "Hausrat", group: shared)

        #expect(!BudgetGroupRelationshipValidator.isValid(budget: budget, in: personal))
        #expect(!BudgetGroupRelationshipValidator.isValid(fixedCost: fixedCost, in: personal))
        #expect(BudgetGroupRelationshipValidator.isValid(budget: budget, in: nil))
        #expect(BudgetGroupRelationshipValidator.isValid(fixedCost: nil, in: personal))
    }

    @Test func budgetGroupMigrationAssignsOrphanedDataEvenWhenAGroupExists() throws {
        let container = try ModelContainer(
            for: UserSettings.self,
            BudgetGroup.self,
            BudgetGroupMonthlyAllocation.self,
            Budget.self,
            Transaction.self,
            FixedCost.self,
            SavingsGoal.self,
            SavingsContribution.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let existingGroup = BudgetGroup(name: "Persönlich")
        let orphanedBudget = Budget(name: "Versicherung")
        let orphanedFixedCost = FixedCost(title: "Hausrat", budget: orphanedBudget)
        let orphanedGoal = SavingsGoal(name: "Urlaub", budget: orphanedBudget)
        let orphanedTransaction = Transaction(
            title: "Hausrat",
            amount: 25,
            type: .expense,
            budget: orphanedBudget
        )

        context.insert(existingGroup)
        context.insert(orphanedBudget)
        context.insert(orphanedFixedCost)
        context.insert(orphanedGoal)
        context.insert(orphanedTransaction)
        try context.save()

        let migratedGroup = try BudgetGroupMigration.ensureDefaultGroupAndMigrate(in: context)

        #expect(migratedGroup.persistentModelID == existingGroup.persistentModelID)
        #expect(orphanedBudget.group?.persistentModelID == existingGroup.persistentModelID)
        #expect(orphanedFixedCost.group?.persistentModelID == existingGroup.persistentModelID)
        #expect(orphanedGoal.group?.persistentModelID == existingGroup.persistentModelID)
        #expect(orphanedTransaction.group?.persistentModelID == existingGroup.persistentModelID)

        let secondRunGroup = try BudgetGroupMigration.ensureDefaultGroupAndMigrate(in: context)
        let groups = try context.fetch(FetchDescriptor<BudgetGroup>())
        #expect(secondRunGroup.persistentModelID == existingGroup.persistentModelID)
        #expect(groups.count == 1)
    }

    @Test func expenseImpactsBudgetAsPositiveAmount() {
        let transaction = Transaction(
            amount: 42.50,
            type: .expense
        )

        #expect(transaction.signedAmount == -42.50)
        #expect(transaction.budgetImpact == 42.50)
    }

    @Test func refundReversesBudgetImpact() {
        let transaction = Transaction(
            amount: 12,
            type: .refund
        )

        #expect(transaction.signedAmount == 12)
        #expect(transaction.budgetImpact == -12)
    }

    @Test func incomeDoesNotConsumeBudget() {
        let transaction = Transaction(
            amount: 100,
            type: .income
        )

        #expect(transaction.signedAmount == 100)
        #expect(transaction.budgetImpact == 0)
    }

    @Test func budgetCalculatesRemainingAmountAndOverflow() {
        let budget = Budget(limit: 100)
        budget.transactions = [
            Transaction(amount: 80, type: .expense, budget: budget),
            Transaction(amount: 30, type: .expense, budget: budget)
        ]

        #expect(budget.spentAmount == 110)
        #expect(budget.remainingAmount == -10)
        #expect(budget.isOverBudget)
        #expect(budget.exceededAmount == 10)
    }

    @Test func negativeTransactionAmountsAreNormalized() {
        let transaction = Transaction(
            amount: -25,
            type: .expense
        )

        #expect(transaction.signedAmount == -25)
        #expect(transaction.budgetImpact == 25)
    }

    @Test func refundsCanOffsetExpenses() {
        let budget = Budget(limit: 100)
        budget.transactions = [
            Transaction(amount: 75, type: .expense, budget: budget),
            Transaction(amount: 20, type: .refund, budget: budget)
        ]

        #expect(budget.spentAmount == 55)
        #expect(budget.remainingAmount == 45)
        #expect(!budget.isOverBudget)
    }

    @Test func unlimitedBudgetHasNoRemainingAmount() {
        let budget = Budget(limit: 0)

        #expect(budget.remainingAmount == nil)
        #expect(!budget.isOverBudget)
        #expect(budget.visualProgress == 0)
    }

    @Test func budgetSpendingIsLimitedToSelectedMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let january = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let february = calendar.date(from: DateComponents(year: 2026, month: 2, day: 15))!
        let budget = Budget(limit: 200)
        budget.transactions = [
            Transaction(amount: 40, date: january, type: .expense, budget: budget),
            Transaction(amount: 60, date: february, type: .expense, budget: budget)
        ]

        #expect(budget.spentAmount(in: january, calendar: calendar) == 40)
        #expect(budget.spentAmount(in: february, calendar: calendar) == 60)
    }

    @Test func supportedCurrenciesHaveStableCodes() {
        #expect(AppCurrency.eur.rawValue == "EUR")
        #expect(AppCurrency.usd.rawValue == "USD")
        #expect(AppCurrency.gbp.rawValue == "GBP")
        #expect(AppCurrency.chf.rawValue == "CHF")
    }

    @Test func fixedCostCalculatesMonthlyEquivalent() {
        let yearly = FixedCost(amount: 120, frequency: .yearly)
        let quarterly = FixedCost(amount: 90, frequency: .quarterly)

        #expect(yearly.monthlyEquivalent == 10)
        #expect(quarterly.monthlyEquivalent == 30)
    }

    @Test func fixedCostUsesLastDayForShortMonths() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let january = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let february = calendar.date(from: DateComponents(year: 2026, month: 2, day: 28))!
        let fixedCost = FixedCost(
            amount: 10,
            frequency: .monthly,
            schedule: .lastDayOfMonth,
            anchorDate: january
        )

        #expect(fixedCost.occurrenceDates(through: february, calendar: calendar).count == 2)
    }

    @Test func savingsGoalWithoutTargetHasNoRemainingAmount() {
        let goal = SavingsGoal(name: "Notgroschen")
        goal.contributions = [
            SavingsContribution(amount: 50, goal: goal)
        ]

        #expect(goal.savedAmount == 50)
        #expect(goal.remainingAmount == nil)
        #expect(!goal.isCompleted)
    }

    @Test func savingsGoalCalculatesProgressAgainstTarget() {
        let goal = SavingsGoal(
            name: "Urlaub",
            targetAmount: 1_000
        )
        goal.contributions = [
            SavingsContribution(amount: 250, goal: goal),
            SavingsContribution(amount: 100, goal: goal)
        ]

        #expect(goal.savedAmount == 350)
        #expect(goal.remainingAmount == 650)
        #expect(abs(goal.progress - 0.35) < 0.0001)
        #expect(!goal.isCompleted)
    }

    @Test func savingsGoalUsesConfiguredMonthlySchedule() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 3, day: 31))!
        let goal = SavingsGoal(
            name: "Urlaub",
            frequency: .monthly,
            schedule: .lastDayOfMonth,
            anchorDate: start
        )

        let dates = goal.occurrenceDates(through: end, calendar: calendar)

        #expect(dates.count == 3)
        #expect(calendar.component(.day, from: dates[0]) == 31)
        #expect(calendar.component(.day, from: dates[1]) == 28)
        #expect(calendar.component(.day, from: dates[2]) == 31)
    }

    @Test func savingsGoalCanReferenceFixedCost() throws {
        let container = try ModelContainer(
            for: FixedCost.self,
            SavingsGoal.self,
            SavingsContribution.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let fixedCost = FixedCost(
            title: "Apple Developer Account",
            amount: 99,
            frequency: .yearly
        )
        let goal = SavingsGoal(
            name: "Apple Developer Account",
            targetAmount: 99,
            fixedCost: fixedCost
        )
        context.insert(fixedCost)
        context.insert(goal)
        try context.save()

        let storedGoal = try context.fetch(FetchDescriptor<SavingsGoal>()).first
        #expect(storedGoal?.fixedCost?.persistentModelID == fixedCost.persistentModelID)
        #expect(fixedCost.savingsGoals?.contains { $0.persistentModelID == goal.persistentModelID } == true)
    }

    @Test func savingsGoalAutomaticBookingCarriesBudgetAndPreventsDuplicates() throws {
        let container = try ModelContainer(
            for: UserSettings.self,
            BudgetGroup.self,
            BudgetGroupMonthlyAllocation.self,
            Budget.self,
            Transaction.self,
            FixedCost.self,
            SavingsGoal.self,
            SavingsContribution.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let group = BudgetGroup(name: "Privat")
        let budget = Budget(name: "Sparen", group: group)
        let goal = SavingsGoal(
            name: "Notgroschen",
            contributionAmount: 100,
            frequency: .monthly,
            anchorDate: Calendar.current.startOfDay(for: .now),
            automaticBooking: true,
            budget: budget,
            group: group
        )
        context.insert(group)
        context.insert(budget)
        context.insert(goal)

        try SavingsGoalScheduler.processAutomaticBookings(
            goals: [goal],
            transactions: [],
            modelContext: context,
            through: .now
        )

        let firstTransactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(firstTransactions.count == 1)
        #expect(firstTransactions.first?.budget?.persistentModelID == budget.persistentModelID)
        #expect(firstTransactions.first?.group?.persistentModelID == group.persistentModelID)

        try SavingsGoalScheduler.processAutomaticBookings(
            goals: [goal],
            transactions: firstTransactions,
            modelContext: context,
            through: .now
        )

        let secondTransactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(secondTransactions.count == 1)
        #expect(goal.savedAmount == 100)
    }

}
