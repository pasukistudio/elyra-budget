import Foundation
import SwiftData

@Model
final class FixedCost {
    var id: UUID = UUID()
    var title: String = ""
    var amount: Decimal = 0
    var frequencyRawValue: String = FixedCostFrequency.monthly.rawValue
    var scheduleRawValue: String = FixedCostSchedule.fixedDay.rawValue
    var anchorDate: Date = Date()
    var dayOfMonth: Int = 1
    var automaticBooking: Bool = true
    var isPaused: Bool = false
    var pauseUntil: Date?
    var note: String = ""
    var budget: Budget?
    /// Optional until the user assigns the fixed cost to a budget group.
    var group: BudgetGroup?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        title: String = "",
        amount: Decimal = 0,
        frequency: FixedCostFrequency = .monthly,
        schedule: FixedCostSchedule = .fixedDay,
        anchorDate: Date = .now,
        dayOfMonth: Int = 1,
        automaticBooking: Bool = true,
        budget: Budget? = nil,
        group: BudgetGroup? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.amount = amount
        self.frequencyRawValue = frequency.rawValue
        self.scheduleRawValue = schedule.rawValue
        self.anchorDate = anchorDate
        self.dayOfMonth = min(max(dayOfMonth, 1), 31)
        self.automaticBooking = automaticBooking
        self.budget = budget
        self.group = group
        self.createdAt = .now
        self.updatedAt = .now
    }

    var frequency: FixedCostFrequency {
        get { FixedCostFrequency(rawValue: frequencyRawValue) ?? .monthly }
        set { frequencyRawValue = newValue.rawValue }
    }

    var schedule: FixedCostSchedule {
        get { FixedCostSchedule(rawValue: scheduleRawValue) ?? .fixedDay }
        set { scheduleRawValue = newValue.rawValue }
    }

    /// Normalizes every recurrence to a comparable monthly amount.
    var monthlyEquivalent: Decimal {
        switch frequency {
        case .daily:
            return amount * 365 / 12
        case .weekly:
            return amount * 52 / 12
        case .monthly:
            return amount
        case .quarterly:
            return amount / 3
        case .halfYearly:
            return amount / 6
        case .yearly:
            return amount / 12
        }
    }

    func isActive(on date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard isPaused else { return true }
        guard let pauseUntil else { return false }
        return calendar.startOfDay(for: date) > calendar.startOfDay(for: pauseUntil)
    }

    func occurrenceDates(
        through endDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [Date] {
        let endOfDay = calendar.startOfDay(for: endDate)
        var occurrences: [Date] = []
        var occurrence = firstOccurrenceDate(calendar: calendar)
        var guardCounter = 0

        while occurrence <= endOfDay && guardCounter < 5000 {
            if occurrence >= calendar.startOfDay(for: anchorDate), isActive(on: occurrence, calendar: calendar) {
                occurrences.append(occurrence)
            }
            guardCounter += 1
            guard let next = nextOccurrence(after: occurrence, calendar: calendar) else { break }
            occurrence = next
        }

        return occurrences
    }

    func nextDueDate(
        after date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        let target = calendar.startOfDay(for: date)
        var occurrence = firstOccurrenceDate(calendar: calendar)
        var guardCounter = 0

        while guardCounter < 5000 {
            if occurrence >= target && isActive(on: occurrence, calendar: calendar) {
                return occurrence
            }
            guard let next = nextOccurrence(after: occurrence, calendar: calendar) else { return nil }
            occurrence = next
            guardCounter += 1
        }
        return nil
    }

    private func nextOccurrence(after date: Date, calendar: Calendar) -> Date? {
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date)
        case .monthly, .quarterly, .halfYearly, .yearly:
            guard let months = frequency.months else { return nil }
            guard let nextMonth = calendar.date(byAdding: .month, value: months, to: date) else { return nil }
            return scheduledDate(in: nextMonth, calendar: calendar)
        }
    }

    private func firstOccurrenceDate(calendar: Calendar) -> Date {
        guard frequency.months != nil else {
            return calendar.startOfDay(for: anchorDate)
        }
        return scheduledDate(in: anchorDate, calendar: calendar)
            ?? calendar.startOfDay(for: anchorDate)
    }

    private func scheduledDate(in date: Date, calendar: Calendar) -> Date? {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return nil }
        let start = interval.start
        let day: Int
        switch schedule {
        case .firstDayOfMonth: day = 1
        case .middleOfMonth: day = 15
        case .lastDayOfMonth: day = calendar.component(.day, from: interval.end.addingTimeInterval(-1))
        case .fixedDay: day = min(max(dayOfMonth, 1), calendar.range(of: .day, in: .month, for: start)?.count ?? dayOfMonth)
        }
        return calendar.date(bySetting: .day, value: day, of: start)
    }
}
