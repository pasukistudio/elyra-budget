import Foundation
import SwiftData

struct FixedCostDueItem: Identifiable {
    let fixedCost: FixedCost
    let dueDate: Date

    var id: String {
        "\(fixedCost.id.uuidString)-\(dueDate.timeIntervalSinceReferenceDate)"
    }
}

enum FixedCostOccurrenceStatus: Equatable {
    case booked
    case due
    case scheduled
}

struct FixedCostOccurrence: Identifiable {
    let dueDate: Date
    let transaction: Transaction?
    let status: FixedCostOccurrenceStatus

    var id: String { dueDate.ISO8601Format() }
}

enum FixedCostScheduler {
    static func processAutomaticBookings(
        fixedCosts: [FixedCost],
        savingsGoals: [SavingsGoal],
        transactions: [Transaction],
        modelContext: ModelContext,
        through date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws {
        var existing = Set(
            transactions.compactMap { transactionMarker(for: $0, calendar: calendar) }
        )

        for fixedCost in fixedCosts where fixedCost.automaticBooking {
            guard BudgetGroupRelationshipValidator.isValid(budget: fixedCost.budget, in: fixedCost.group) else {
                continue
            }

            for dueDate in fixedCost.occurrenceDates(through: date, calendar: calendar) {
                let marker = marker(for: fixedCost.id, date: dueDate, calendar: calendar)
                guard !existing.contains(marker) else { continue }

                createBooking(
                    for: fixedCost,
                    dueDate: dueDate,
                    savingsGoals: savingsGoals,
                    automatic: true,
                    modelContext: modelContext
                )
                existing.insert(marker)
            }
        }

        guard modelContext.hasChanges else { return }
        try modelContext.save()
    }

    static func book(
        fixedCost: FixedCost,
        dueDate: Date,
        savingsGoals: [SavingsGoal],
        modelContext: ModelContext
    ) throws {
        createBooking(
            for: fixedCost,
            dueDate: dueDate,
            savingsGoals: savingsGoals,
            automatic: false,
            modelContext: modelContext
        )
        try modelContext.save()
    }

    private static func createBooking(
        for fixedCost: FixedCost,
        dueDate: Date,
        savingsGoals: [SavingsGoal],
        automatic: Bool,
        modelContext: ModelContext
    ) {
        let linkedGoal = savingsGoals.first {
            !$0.isArchived && $0.type == .goal && $0.fixedCost === fixedCost
        }
        let availableAmount = linkedGoal?.savedAmount(asOf: dueDate) ?? 0
        let coveredAmount = min(max(availableAmount, 0), fixedCost.amount)

        if let linkedGoal, coveredAmount > 0 {
            let redemption = SavingsContribution(
                amount: -coveredAmount,
                date: dueDate,
                note: "Fixkosten bezahlt: \(fixedCost.title)",
                automatic: true,
                occurrenceDate: dueDate,
                goal: linkedGoal
            )
            modelContext.insert(redemption)
        }

        let transaction = Transaction(
            title: fixedCost.title,
            amount: fixedCost.amount,
            date: dueDate,
            note: fixedCost.note,
            type: .expense,
            budget: fixedCost.budget,
            group: fixedCost.group ?? fixedCost.budget?.group
        )
        transaction.fixedCostID = fixedCost.id
        transaction.fixedCostOccurrenceDate = dueDate
        transaction.fixedCostBookingAutomatic = automatic
        transaction.savingsGoalCoveredAmount = coveredAmount > 0 ? coveredAmount : nil
        modelContext.insert(transaction)
    }

    static func pendingManualBookings(
        fixedCosts: [FixedCost],
        transactions: [Transaction],
        through date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [FixedCostDueItem] {
        let existing = Set(
            transactions.compactMap { transactionMarker(for: $0, calendar: calendar) }
        )

        return fixedCosts
            .filter { !$0.automaticBooking }
            .flatMap { fixedCost in
                fixedCost.occurrenceDates(through: date, calendar: calendar)
                    .filter {
                        !existing.contains(
                            marker(for: fixedCost.id, date: $0, calendar: calendar)
                        )
                    }
                    .map { FixedCostDueItem(fixedCost: fixedCost, dueDate: $0) }
            }
            .sorted { $0.dueDate < $1.dueDate }
    }

    static func history(
        for fixedCost: FixedCost,
        transactions: [Transaction],
        through date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [FixedCostOccurrence] {
        let linkedTransactions = transactions
            .filter { $0.fixedCostID == fixedCost.id && $0.fixedCostOccurrenceDate != nil }
            .sorted { ($0.fixedCostOccurrenceDate ?? .distantPast) < ($1.fixedCostOccurrenceDate ?? .distantPast) }

        var transactionByDate: [String: Transaction] = [:]
        for transaction in linkedTransactions {
            guard let occurrenceDate = transaction.fixedCostOccurrenceDate else { continue }
            let key = dayKey(for: occurrenceDate, calendar: calendar)
            transactionByDate[key] = transactionByDate[key] ?? transaction
        }
        let currentDay = calendar.startOfDay(for: date)
        let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDay)
            .flatMap { fixedCost.nextDueDate(after: $0, calendar: calendar) }
        let scheduledDates = fixedCost.occurrenceDates(
            through: nextDate ?? currentDay,
            calendar: calendar
        )
        let allKeys = Set(transactionByDate.keys).union(
            scheduledDates.map { dayKey(for: $0, calendar: calendar) }
        )

        return allKeys.compactMap { key in
            guard let occurrenceDate = (
                transactionByDate[key]?.fixedCostOccurrenceDate
                    ?? scheduledDates.first(where: { dayKey(for: $0, calendar: calendar) == key })
            ) else { return nil }

            if let transaction = transactionByDate[key] {
                return FixedCostOccurrence(dueDate: occurrenceDate, transaction: transaction, status: .booked)
            }

            return FixedCostOccurrence(
                dueDate: occurrenceDate,
                transaction: nil,
                status: occurrenceDate <= calendar.startOfDay(for: date) && !fixedCost.automaticBooking
                    ? .due
                    : .scheduled
            )
        }
        .sorted { $0.dueDate > $1.dueDate }
    }

    static func marker(
        for id: UUID,
        date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        "\(id.uuidString)-\(dayKey(for: date, calendar: calendar))"
    }

    private static func transactionMarker(
        for transaction: Transaction,
        calendar: Calendar
    ) -> String? {
        guard let id = transaction.fixedCostID,
              let date = transaction.fixedCostOccurrenceDate else {
            return nil
        }
        return marker(for: id, date: date, calendar: calendar)
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}
