//
//  ElyraBudgetTests.swift
//  ElyraBudgetTests
//
//  Created by Pascal Smigielski on 04.08.26.
//

import Foundation
import CoreData
import SwiftData
import Testing
@testable import ElyraBudget

struct ElyraBudgetTests {

    @Test func cloudKitSyncMonitorDisablesItselfForLocalTestStorage() {
        let monitor = CloudKitSyncMonitor(environment: ["ELYRA_BUDGET_USE_CLOUDKIT": "NO"])

        #expect(monitor.status == .unavailable)
        #expect(monitor.lastSyncDate == nil)
    }

    @Test func cloudKitSyncMonitorReportsSyncFailure() {
        let monitor = CloudKitSyncMonitor(environment: ["CloudKit": "YES"])

        monitor.handle(
            type: .export,
            isFinished: false,
            succeeded: false,
            error: nil
        )
        #expect(monitor.status == .syncing)

        monitor.handle(
            type: .export,
            isFinished: true,
            succeeded: false,
            error: NSError(domain: "CloudKit", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Test synchronization failed"
            ])
        )

        #expect(monitor.status == .failed)
        #expect(monitor.errorMessage == "Test synchronization failed")
    }

    @Test func cloudKitSyncMonitorRecordsSuccessfulSync() {
        let monitor = CloudKitSyncMonitor(environment: ["CloudKit": "YES"])

        monitor.handle(
            type: .import,
            isFinished: true,
            succeeded: true,
            error: nil
        )

        #expect(monitor.status == .succeeded)
        #expect(monitor.lastSyncDate != nil)
        #expect(monitor.errorMessage == nil)
    }

    @Test func budgetGroupUsesMonthlyOverrideBeforeStandardAllowance() {
        let calendar = Calendar.current
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

    @Test func transactionResolvesGroupFromAssignedBudget() {
        let group = BudgetGroup(name: "Gemeinsam")
        let budget = Budget(name: "Versicherung", group: group)
        let transaction = Transaction(title: "Hausrat", budget: budget)

        #expect(transaction.group == nil)
        #expect(transaction.effectiveGroup === group)
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

    @Test func fixedCostSupportsDailyAndWeeklyRecurrence() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15))!

        let daily = FixedCost(amount: 5, frequency: .daily, anchorDate: start)
        let weekly = FixedCost(amount: 10, frequency: .weekly, anchorDate: start)

        #expect(daily.occurrenceDates(through: end, calendar: calendar).count == 15)
        #expect(weekly.occurrenceDates(through: end, calendar: calendar).count == 3)
    }

    @Test func fixedCostSupportsQuarterlyHalfYearlyAndYearlyRecurrence() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let end = calendar.date(from: DateComponents(year: 2027, month: 1, day: 15))!

        let quarterly = FixedCost(amount: 90, frequency: .quarterly, anchorDate: start)
        let halfYearly = FixedCost(amount: 120, frequency: .halfYearly, anchorDate: start)
        let yearly = FixedCost(amount: 240, frequency: .yearly, anchorDate: start)

        #expect(quarterly.occurrenceDates(through: end, calendar: calendar).count == 4)
        #expect(halfYearly.occurrenceDates(through: end, calendar: calendar).count == 2)
        #expect(yearly.occurrenceDates(through: end, calendar: calendar).count == 1)
    }

    @Test func fixedCostSupportsFirstAndMiddleOfMonthSchedules() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31))!

        let firstDay = FixedCost(
            amount: 10,
            frequency: .monthly,
            schedule: .firstDayOfMonth,
            anchorDate: start
        )
        let middleDay = FixedCost(
            amount: 10,
            frequency: .monthly,
            schedule: .middleOfMonth,
            anchorDate: start
        )

        let firstDates = firstDay.occurrenceDates(through: end, calendar: calendar)
        let middleDates = middleDay.occurrenceDates(through: end, calendar: calendar)
        #expect(firstDates.count == 2)
        #expect(middleDates.count == 2)
        #expect(firstDates.allSatisfy { calendar.component(.day, from: $0) == 1 })
        #expect(middleDates.allSatisfy { calendar.component(.day, from: $0) == 15 })
    }

    @Test func pausedFixedCostSkipsOccurrencesUntilPauseEnds() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let pauseUntil = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let fixedCost = FixedCost(
            amount: 10,
            frequency: .monthly,
            anchorDate: start
        )
        fixedCost.isPaused = true
        fixedCost.pauseUntil = pauseUntil

        let dates = fixedCost.occurrenceDates(through: end, calendar: calendar)
        #expect(dates.count == 2)
        #expect(calendar.component(.month, from: dates[0]) == 9)
        #expect(calendar.component(.month, from: dates[1]) == 10)
    }

    @Test func fixedCostAutomaticBookingPreservesBudgetAndPreventsDuplicates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let container = try ModelContainer(
            for: BudgetGroup.self,
            Budget.self,
            Transaction.self,
            FixedCost.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let group = BudgetGroup(name: "Persönlich")
        let budget = Budget(name: "Versicherung", group: group)
        let fixedCost = FixedCost(
            title: "Hausrat",
            amount: 25,
            frequency: .monthly,
            anchorDate: date,
            automaticBooking: true,
            budget: budget,
            group: group
        )
        context.insert(group)
        context.insert(budget)
        context.insert(fixedCost)

        try FixedCostScheduler.processAutomaticBookings(
            fixedCosts: [fixedCost],
            savingsGoals: [],
            transactions: [],
            modelContext: context,
            through: date,
            calendar: calendar
        )
        let firstTransactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(firstTransactions.count == 1)
        #expect(firstTransactions.first?.budget?.persistentModelID == budget.persistentModelID)
        #expect(firstTransactions.first?.group?.persistentModelID == group.persistentModelID)

        try FixedCostScheduler.processAutomaticBookings(
            fixedCosts: [fixedCost],
            savingsGoals: [],
            transactions: firstTransactions,
            modelContext: context,
            through: date,
            calendar: calendar
        )
        #expect(try context.fetch(FetchDescriptor<Transaction>()).count == 1)
    }

    @Test func fixedCostChangesApplyOnlyToFutureOccurrences() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let january = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let august = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let december = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31))!
        let fixedCost = FixedCost(
            amount: 25,
            frequency: .monthly,
            anchorDate: january
        )
        fixedCost.configurationEffectiveDate = august

        let dates = fixedCost.occurrenceDates(through: december, calendar: calendar)

        #expect(dates.count == 5)
        #expect(dates.first == august)
        #expect(dates.last == calendar.date(from: DateComponents(year: 2026, month: 12, day: 1))!)
    }

    @Test func fixedCostHistoryDistinguishesBookedDueAndScheduledOccurrences() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
        let fixedCost = FixedCost(
            title: "Hausrat",
            amount: 25,
            frequency: .monthly,
            anchorDate: start,
            automaticBooking: false
        )
        let transaction = Transaction(title: "Hausrat", amount: 25, date: start, type: .expense)
        transaction.fixedCostID = fixedCost.id
        transaction.fixedCostOccurrenceDate = start
        transaction.fixedCostBookingAutomatic = false

        let history = FixedCostScheduler.history(
            for: fixedCost,
            transactions: [transaction],
            through: today,
            calendar: calendar
        )

        #expect(history.count == 2)
        #expect(history.first?.status == .scheduled)
        #expect(history.last?.status == .booked)
        #expect(history.last?.transaction?.fixedCostBookingAutomatic == false)
    }

    @Test func manualFixedCostProducesPendingBooking() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let fixedCost = FixedCost(
            title: "Hausrat",
            amount: 25,
            frequency: .monthly,
            anchorDate: date,
            automaticBooking: false
        )

        let pending = FixedCostScheduler.pendingManualBookings(
            fixedCosts: [fixedCost],
            transactions: [],
            through: date,
            calendar: calendar
        )

        #expect(pending.count == 1)
        #expect(pending.first?.fixedCost.id == fixedCost.id)
        #expect(pending.first?.dueDate == date)
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

    @Test func savingsGoalForecastUsesAutomaticMonthlyRate() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let goal = SavingsGoal(
            name: "Developer Account",
            targetAmount: 99,
            targetDate: calendar.date(from: DateComponents(year: 2026, month: 12, day: 1)),
            contributionAmount: 10,
            anchorDate: date,
            automaticBooking: true
        )

        let forecast = SavingsGoalForecast.calculate(for: goal, asOf: date, calendar: calendar)

        #expect(forecast.monthlyRate == 10)
        #expect(forecast.requiredMonthlyAmount == 9)
        #expect(forecast.estimatedCompletionDate != nil)
    }

    @Test func savingsGoalForecastUsesContributionHistoryWhenManual() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let january = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let march = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let goal = SavingsGoal(name: "Urlaub", targetAmount: 1_000)
        goal.contributions = [
            SavingsContribution(amount: 100, date: january, goal: goal),
            SavingsContribution(amount: 100, date: march, goal: goal)
        ]

        let forecast = SavingsGoalForecast.calculate(for: goal, asOf: march, calendar: calendar)

        #expect(forecast.monthlyRate == 100)
        #expect(forecast.requiredMonthlyAmount == nil)
    }

    @Test func completedSavingsGoalForecastDoesNotProduceInvalidValues() {
        let goal = SavingsGoal(name: "Erreicht", targetAmount: 100)
        goal.contributions = [SavingsContribution(amount: 125, goal: goal)]

        let forecast = SavingsGoalForecast.calculate(for: goal)

        #expect(forecast.requiredMonthlyAmount == 0)
        #expect(forecast.estimatedCompletionDate == nil)
        #expect(forecast.isOnTrack == true)
    }

    @Test func savingsGoalCalculatesHistoricalBalanceAtMonthEnd() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let january = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let february = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let goal = SavingsGoal(name: "Urlaub", targetAmount: 1_000)
        goal.contributions = [
            SavingsContribution(amount: 100, date: january, goal: goal),
            SavingsContribution(amount: 50, date: february, goal: goal)
        ]

        #expect(goal.savedAmount(asOf: january, calendar: calendar) == 100)
        #expect(goal.savedAmount(asOf: february, calendar: calendar) == 150)
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

    @Test func automaticSavingsBookingSkipsCrossGroupBudgetAssignments() throws {
        let container = try ModelContainer(
            for: BudgetGroup.self,
            Budget.self,
            Transaction.self,
            SavingsGoal.self,
            SavingsContribution.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let personal = BudgetGroup(name: "Persönlich")
        let shared = BudgetGroup(name: "Gemeinsam")
        let personalBudget = Budget(name: "Sparen", group: personal)
        let goal = SavingsGoal(
            name: "Ungültige Zuordnung",
            contributionAmount: 25,
            anchorDate: Calendar.current.startOfDay(for: .now),
            automaticBooking: true,
            budget: personalBudget,
            group: shared
        )
        context.insert(personal)
        context.insert(shared)
        context.insert(personalBudget)
        context.insert(goal)

        try SavingsGoalScheduler.processAutomaticBookings(
            goals: [goal],
            transactions: [],
            modelContext: context,
            through: .now
        )

        #expect(try context.fetch(FetchDescriptor<Transaction>()).isEmpty)
    }

}
