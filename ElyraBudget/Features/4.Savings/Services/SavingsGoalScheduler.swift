import Foundation
import SwiftData

enum SavingsGoalScheduler {
    static func processAutomaticBookings(
        goals: [SavingsGoal],
        transactions: [Transaction],
        modelContext: ModelContext,
        through date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws {
        var existing = Set(
            transactions.compactMap { transactionMarker(for: $0, calendar: calendar) }
        )

        for goal in goals where !goal.isArchived && goal.automaticBooking && goal.contributionAmount > 0 {
            guard BudgetGroupRelationshipValidator.isValid(budget: goal.budget, in: goal.group) else {
                continue
            }

            for occurrenceDate in goal.occurrenceDates(through: date, calendar: calendar) {
                let marker = marker(for: goal.id, date: occurrenceDate, calendar: calendar)
                guard !existing.contains(marker) else { continue }

                let contribution = SavingsContribution(
                    amount: goal.contributionAmount,
                    date: occurrenceDate,
                    note: goal.note,
                    automatic: true,
                    occurrenceDate: occurrenceDate,
                    goal: goal
                )

                let transaction = Transaction(
                    title: goal.name,
                    amount: goal.contributionAmount,
                    date: occurrenceDate,
                    note: goal.note,
                    type: .expense,
                    budget: goal.budget,
                    group: goal.group ?? goal.budget?.group
                )
                transaction.savingsGoalID = goal.id
                transaction.savingsGoalOccurrenceDate = occurrenceDate
                transaction.savingsContributionID = contribution.id
                contribution.transactionID = transaction.id
                modelContext.insert(contribution)
                modelContext.insert(transaction)
                existing.insert(marker)
            }
        }

        guard modelContext.hasChanges else { return }
        try modelContext.save()
    }

    static func marker(
        for id: UUID,
        date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(id.uuidString)-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private static func transactionMarker(
        for transaction: Transaction,
        calendar: Calendar
    ) -> String? {
        guard let id = transaction.savingsGoalID,
              let date = transaction.savingsGoalOccurrenceDate
        else { return nil }
        return marker(for: id, date: date, calendar: calendar)
    }
}
