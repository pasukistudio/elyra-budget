import Foundation
import SwiftData

struct FixedCostDueItem: Identifiable {
    let fixedCost: FixedCost
    let dueDate: Date

    var id: String {
        "\(fixedCost.id.uuidString)-\(dueDate.timeIntervalSinceReferenceDate)"
    }
}

enum FixedCostScheduler {
    static func processAutomaticBookings(
        fixedCosts: [FixedCost],
        transactions: [Transaction],
        modelContext: ModelContext,
        through date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws {
        var existing = Set(
            transactions.compactMap { transactionMarker(for: $0, calendar: calendar) }
        )

        for fixedCost in fixedCosts where fixedCost.automaticBooking {
            for dueDate in fixedCost.occurrenceDates(through: date, calendar: calendar) {
                let marker = marker(for: fixedCost.id, date: dueDate, calendar: calendar)
                guard !existing.contains(marker) else { continue }

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
                modelContext.insert(transaction)
                existing.insert(marker)
            }
        }

        try modelContext.save()
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
