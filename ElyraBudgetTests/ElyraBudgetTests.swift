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

}
