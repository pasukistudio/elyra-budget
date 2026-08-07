import Foundation
import SwiftData

@Model
final class SavingsGoal {
    var id: UUID = UUID()
    var name: String = ""
    var typeRawValue: String = SavingsGoalType.goal.rawValue
    var targetAmount: Decimal?
    var contributionAmount: Decimal = 0
    var frequencyRawValue: String = SavingsFrequency.monthly.rawValue
    var scheduleRawValue: String = SavingsSchedule.fixedDay.rawValue
    var anchorDate: Date = Date()
    var dayOfMonth: Int = 1
    var automaticBooking: Bool = false
    var note: String = ""
    var iconName: String = "banknote"
    var iconColorHex: String = "#34C759"
    var sortOrder: Int = 0
    var isArchived: Bool = false
    /// Optional until the user assigns the savings item to a budget group.
    var group: BudgetGroup?
    var budget: Budget?

    @Relationship(
        deleteRule: .cascade,
        inverse: \SavingsContribution.goal
    )
    var contributions: [SavingsContribution]? = []

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        name: String = "",
        type: SavingsGoalType = .goal,
        targetAmount: Decimal? = nil,
        contributionAmount: Decimal = 0,
        frequency: SavingsFrequency = .monthly,
        schedule: SavingsSchedule = .fixedDay,
        anchorDate: Date = .now,
        automaticBooking: Bool = false,
        budget: Budget? = nil,
        group: BudgetGroup? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.typeRawValue = type.rawValue
        self.targetAmount = targetAmount
        self.contributionAmount = contributionAmount
        self.frequencyRawValue = frequency.rawValue
        self.scheduleRawValue = schedule.rawValue
        self.anchorDate = anchorDate
        self.dayOfMonth = min(max(Calendar.current.component(.day, from: anchorDate), 1), 31)
        self.automaticBooking = automaticBooking
        self.budget = budget
        self.group = group
        self.createdAt = .now
        self.updatedAt = .now
    }

    var type: SavingsGoalType {
        get { SavingsGoalType(rawValue: typeRawValue) ?? .goal }
        set { typeRawValue = newValue.rawValue }
    }

    var frequency: SavingsFrequency {
        get { SavingsFrequency(rawValue: frequencyRawValue) ?? .monthly }
        set { frequencyRawValue = newValue.rawValue }
    }

    var schedule: SavingsSchedule {
        get { SavingsSchedule(rawValue: scheduleRawValue) ?? .fixedDay }
        set { scheduleRawValue = newValue.rawValue }
    }

    var savedAmount: Decimal {
        (contributions ?? []).reduce(.zero) { $0 + $1.amount }
    }

    var remainingAmount: Decimal? {
        guard let targetAmount, targetAmount > 0 else { return nil }
        return max(targetAmount - savedAmount, 0)
    }

    var progress: Double {
        guard let targetAmount, targetAmount > 0 else { return 0 }
        return NSDecimalNumber(decimal: savedAmount / targetAmount).doubleValue
    }

    var visualProgress: Double { min(max(progress, 0), 1) }

    var isCompleted: Bool {
        guard let targetAmount, targetAmount > 0 else { return false }
        return savedAmount >= targetAmount
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
            if occurrence >= calendar.startOfDay(for: anchorDate) {
                occurrences.append(occurrence)
            }
            guardCounter += 1
            guard let next = nextOccurrence(after: occurrence, calendar: calendar) else { break }
            occurrence = next
        }

        return occurrences
    }

    private func nextOccurrence(after date: Date, calendar: Calendar) -> Date? {
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date)
        case .monthly, .quarterly, .halfYearly, .yearly:
            guard let months = frequency.months,
                  let nextMonth = calendar.date(byAdding: .month, value: months, to: date)
            else { return nil }
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
        case .lastDayOfMonth:
            day = calendar.component(.day, from: interval.end.addingTimeInterval(-1))
        case .fixedDay:
            day = min(
                max(dayOfMonth, 1),
                calendar.range(of: .day, in: .month, for: start)?.count ?? dayOfMonth
            )
        }
        return calendar.date(bySetting: .day, value: day, of: start)
    }
}
