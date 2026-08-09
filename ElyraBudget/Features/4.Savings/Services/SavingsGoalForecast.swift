import Foundation

struct SavingsGoalForecast {
    let monthlyRate: Decimal?
    let requiredMonthlyAmount: Decimal?
    let estimatedCompletionDate: Date?
    let isOnTrack: Bool?
    let explanation: String?

    static func calculate(
        for goal: SavingsGoal,
        asOf date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> SavingsGoalForecast {
        let savedAmount = goal.savedAmount(asOf: date, calendar: calendar)
        let monthlyRate = monthlyRate(for: goal, asOf: date, calendar: calendar)
        let remainingAmount: Decimal? = {
            guard let targetAmount = goal.targetAmount, targetAmount > 0 else { return nil }
            return max(targetAmount - savedAmount, .zero)
        }()

        guard let remainingAmount else {
            return SavingsGoalForecast(
                monthlyRate: monthlyRate,
                requiredMonthlyAmount: nil,
                estimatedCompletionDate: nil,
                isOnTrack: nil,
                explanation: "Für dieses Sparziel ist kein Zielbetrag festgelegt."
            )
        }

        if remainingAmount == .zero {
            return SavingsGoalForecast(
                monthlyRate: monthlyRate,
                requiredMonthlyAmount: .zero,
                estimatedCompletionDate: nil,
                isOnTrack: true,
                explanation: "Dieses Sparziel ist erreicht."
            )
        }

        let requiredMonthlyAmount = requiredMonthlyAmount(
            remainingAmount: remainingAmount,
            targetDate: goal.targetDate,
            asOf: date,
            calendar: calendar
        )
        let estimatedCompletionDate = completionDate(
            remainingAmount: remainingAmount,
            monthlyRate: monthlyRate,
            asOf: date,
            calendar: calendar
        )

        let isOnTrack: Bool? = {
            guard let targetDate = goal.targetDate,
                  let completionDate = estimatedCompletionDate else {
                return nil
            }
            return completionDate <= calendar.startOfDay(for: targetDate)
        }()

        let explanation: String? = {
            if monthlyRate == nil {
                return "Noch nicht genug Einzahlungen für eine verlässliche Prognose."
            }
            if let targetDate = goal.targetDate, targetDate < calendar.startOfDay(for: date) {
                return "Das Zieldatum ist bereits überschritten."
            }
            if isOnTrack == false {
                return "Der aktuelle Sparbetrag reicht voraussichtlich nicht bis zum Zieldatum."
            }
            return nil
        }()

        return SavingsGoalForecast(
            monthlyRate: monthlyRate,
            requiredMonthlyAmount: requiredMonthlyAmount,
            estimatedCompletionDate: estimatedCompletionDate,
            isOnTrack: isOnTrack,
            explanation: explanation
        )
    }

    private static func monthlyRate(
        for goal: SavingsGoal,
        asOf date: Date,
        calendar: Calendar
    ) -> Decimal? {
        if goal.automaticBooking, goal.contributionAmount > 0 {
            let amount = goal.contributionAmount
            switch goal.frequency {
            case .daily: return amount * 365 / 12
            case .weekly: return amount * 52 / 12
            case .monthly: return amount
            case .quarterly: return amount / 3
            case .halfYearly: return amount / 6
            case .yearly: return amount / 12
            }
        }

        let contributions = (goal.contributions ?? [])
            .filter { $0.date <= date }
        guard let firstDate = contributions.map(\.date).min(), !contributions.isEmpty else {
            return nil
        }

        let total = contributions.reduce(.zero) { $0 + $1.amount }
        guard total > 0 else { return nil }

        let firstMonth = calendar.dateInterval(of: .month, for: firstDate)?.start ?? firstDate
        let currentMonth = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let monthCount = max(
            calendar.dateComponents([.month], from: firstMonth, to: currentMonth).month ?? 0,
            0
        ) + 1
        return total / Decimal(monthCount)
    }

    private static func requiredMonthlyAmount(
        remainingAmount: Decimal,
        targetDate: Date?,
        asOf date: Date,
        calendar: Calendar
    ) -> Decimal? {
        guard let targetDate else { return nil }
        let currentMonth = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let targetMonth = calendar.dateInterval(of: .month, for: targetDate)?.start ?? targetDate
        let months = max(
            calendar.dateComponents([.month], from: currentMonth, to: targetMonth).month ?? 0,
            1
        )
        return rounded(remainingAmount / Decimal(months))
    }

    private static func completionDate(
        remainingAmount: Decimal,
        monthlyRate: Decimal?,
        asOf date: Date,
        calendar: Calendar
    ) -> Date? {
        guard let monthlyRate, monthlyRate > 0 else { return nil }
        let months = max(
            Int(ceil(NSDecimalNumber(decimal: remainingAmount / monthlyRate).doubleValue)),
            1
        )
        let currentMonth = calendar.dateInterval(of: .month, for: date)?.start ?? date
        return calendar.date(byAdding: .month, value: months, to: currentMonth)
    }

    private static func rounded(_ value: Decimal) -> Decimal {
        var value = value
        var roundedValue = Decimal.zero
        NSDecimalRound(&roundedValue, &value, 2, .plain)
        return roundedValue
    }
}
