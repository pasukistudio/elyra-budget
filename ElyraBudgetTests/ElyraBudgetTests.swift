//
//  ElyraBudgetTests.swift
//  ElyraBudgetTests
//
//  Created by Pascal Smigielski on 04.08.26.
//

import Foundation
import Testing
@testable import ElyraBudget

struct ElyraBudgetTests {

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

}
