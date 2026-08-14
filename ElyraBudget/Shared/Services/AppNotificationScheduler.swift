import Foundation
import OSLog
import UserNotifications

enum AppNotificationScheduler {
    private static let budgetPrefix = "budget-warning-"
    private static let savingsPrefix = "savings-contribution-"
    private static let syncPrefix = "icloud-sync-error-"
    private static let goalPrefix = "savings-goal-completed-"
    private static let failurePrefix = "automatic-booking-failure-"
    private static let summaryPrefix = "monthly-summary-"
    private static let forecastPrefix = "savings-forecast-risk-"
    private static let overduePrefix = "fixed-cost-overdue-"
    private static let unusualExpensePrefix = "unusual-expense-"
    private static let syncRecoveryPrefix = "icloud-sync-recovered-"
    private static let dailyDigestIdentifier = "daily-digest"
    private static let reminderHour = 9

    static func reschedule(
        fixedCosts: [FixedCost],
        savingsGoals: [SavingsGoal],
        budgets: [Budget],
        transactions: [Transaction],
        settings: UserSettings?,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) async {
        configureQuietHours(using: settings)
        await FixedCostNotificationScheduler.reschedule(
            fixedCosts: fixedCosts,
            transactions: transactions,
            now: now,
            calendar: calendar
        )

        let center = UNUserNotificationCenter.current()
        let pendingRequests = await pendingNotificationRequests(from: center)
        let removablePrefixes = [
            budgetPrefix,
            savingsPrefix,
            goalPrefix,
            summaryPrefix,
            forecastPrefix,
            overduePrefix,
            unusualExpensePrefix,
            failurePrefix,
            dailyDigestIdentifier
        ]
        let oldIdentifiers = pendingRequests
            .map { $0.identifier }
            .filter { identifier in
                removablePrefixes.contains { identifier.hasPrefix($0) }
            }
        center.removePendingNotificationRequests(withIdentifiers: oldIdentifiers)

        let authorization = await center.notificationSettings().authorizationStatus
        guard authorization == .authorized || authorization == .provisional else {
            return
        }

        if settings?.budgetNotificationsEnabled ?? true {
            await scheduleBudgetWarnings(
                budgets: budgets,
                transactions: transactions,
                settings: settings,
                center: center,
                now: now,
                calendar: calendar
            )
        }

        if settings?.savingsContributionNotificationsEnabled ?? true {
            await scheduleSavingsContributions(
                goals: savingsGoals,
                transactions: transactions,
                center: center,
                now: now,
                calendar: calendar
            )
        }

        if settings?.savingsGoalCompletionNotificationsEnabled ?? true {
            await scheduleCompletedSavingsGoals(
                goals: savingsGoals,
                center: center
            )
        }

        if settings?.monthlySummaryNotificationsEnabled ?? true {
            await scheduleMonthlySummary(
                transactions: transactions,
                center: center,
                now: now,
                calendar: calendar
            )
        }

        if settings?.forecastRiskNotificationsEnabled ?? true {
            await scheduleForecastRisks(
                goals: savingsGoals,
                center: center,
                now: now,
                calendar: calendar
            )
        }

        if settings?.overdueFixedCostNotificationsEnabled ?? true {
            await scheduleOverdueFixedCosts(
                fixedCosts: fixedCosts,
                transactions: transactions,
                center: center,
                now: now,
                calendar: calendar
            )
        }

        if settings?.unusualExpenseNotificationsEnabled ?? false {
            await scheduleUnusualExpenses(
                transactions: transactions,
                center: center,
                now: now,
                calendar: calendar
            )
        }

        if settings?.dailyDigestNotificationsEnabled ?? false {
            await scheduleDailyDigest(
                transactions: transactions,
                center: center,
                now: now,
                calendar: calendar
            )
        }
    }

    static func scheduleAutomaticBookingFailure(
        message: String,
        enabled: Bool,
        now: Date = .now,
        center: UNUserNotificationCenter = .current()
    ) async {
        guard enabled else { return }
        let authorization = await center.notificationSettings().authorizationStatus
        guard authorization == .authorized || authorization == .provisional else { return }

        let identifier = "\(failurePrefix)\(dayKey(for: now, calendar: .autoupdatingCurrent))"
        let content = UNMutableNotificationContent()
        content.title = "Automatische Buchung fehlgeschlagen"
        content.body = message
        content.sound = .default
        content.threadIdentifier = "bookings"
        content.categoryIdentifier = "bookings"

        do {
            try await center.add(
                UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: immediateTrigger()
                )
            )
        } catch {
            AppLogger.persistence.error(
                "Buchungsfehlerbenachrichtigung konnte nicht geplant werden: \(error)"
            )
        }
    }

    static func scheduleSyncError(
        message: String,
        enabled: Bool,
        now: Date = .now,
        center: UNUserNotificationCenter = .current()
    ) async {
        let pendingRequests = await pendingNotificationRequests(from: center)
        let oldIdentifiers = pendingRequests
            .map { $0.identifier }
            .filter { $0.hasPrefix(syncPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: oldIdentifiers)

        guard enabled else { return }
        let authorization = await center.notificationSettings().authorizationStatus
        guard authorization == .authorized || authorization == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "iCloud-Synchronisierung fehlgeschlagen"
        content.body = message
        content.sound = .default
        content.threadIdentifier = "sync"
        content.categoryIdentifier = "sync"

        let trigger = immediateTrigger()
        let identifier = "\(syncPrefix)\(dayKey(for: now, calendar: .autoupdatingCurrent))"
        do {
            try await center.add(
                UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: trigger
                )
            )
        } catch {
            AppLogger.persistence.error(
                "iCloud-Fehlerbenachrichtigung konnte nicht geplant werden: \(error)"
            )
        }
    }

    static func scheduleSyncRecovery(
        enabled: Bool,
        now: Date = .now,
        center: UNUserNotificationCenter = .current()
    ) async {
        guard enabled else { return }
        let authorization = await center.notificationSettings().authorizationStatus
        guard authorization == .authorized || authorization == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "iCloud wieder synchronisiert"
        content.body = "Deine Daten werden wieder erfolgreich synchronisiert."
        content.sound = .default
        content.threadIdentifier = "sync"
        let identifier = "\(syncRecoveryPrefix)\(dayKey(for: now, calendar: .autoupdatingCurrent))"
        do {
            try await center.add(
                UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: immediateTrigger()
                )
            )
        } catch {
            AppLogger.persistence.error(
                "Sync-Wiederherstellungsbenachrichtigung konnte nicht geplant werden: \(error)"
            )
        }
    }

    private static func scheduleBudgetWarnings(
        budgets: [Budget],
        transactions: [Transaction],
        settings: UserSettings?,
        center: UNUserNotificationCenter,
        now: Date,
        calendar: Calendar
    ) async {
        let thresholds = [
            settings?.greenBudgetThreshold ?? 70,
            settings?.orangeBudgetThreshold ?? 100
        ].filter { $0 > 0 }.sorted().removingDuplicates()

        for budget in budgets where !budget.isArchived && budget.limit > 0 {
            let spent = transactions
                .filter { $0.budget === budget && $0.date.isInSameMonth(as: now, calendar: calendar) }
                .reduce(Decimal.zero) { $0 + $1.budgetImpact }
            let progress = NSDecimalNumber(decimal: spent / budget.limit).doubleValue * 100

            for threshold in thresholds where progress >= Double(threshold) {
                let key = "elyraBudget.notification.budget.\(budget.name).\(dayKey(for: now, calendar: calendar)).\(threshold)"
                guard !UserDefaults.standard.bool(forKey: key) else { continue }

                let content = UNMutableNotificationContent()
                content.title = "Budgetwarnung"
                content.body = "\(budget.name) hat \(threshold) % des Monatsbudgets erreicht."
                content.sound = .default
                content.threadIdentifier = "budget"
                content.categoryIdentifier = "budget"
                let request = UNNotificationRequest(
                    identifier: "\(budgetPrefix)\(UUID().uuidString)",
                    content: content,
                    trigger: immediateTrigger()
                )
                do {
                    try await center.add(request)
                    UserDefaults.standard.set(true, forKey: key)
                } catch {
                    AppLogger.persistence.error(
                        "Budgetwarnung konnte nicht geplant werden: \(error)"
                    )
                }
            }
        }
    }

    private static func scheduleSavingsContributions(
        goals: [SavingsGoal],
        transactions: [Transaction],
        center: UNUserNotificationCenter,
        now: Date,
        calendar: Calendar
    ) async {
        let bookedMarkers = Set(
            transactions.compactMap { transaction -> String? in
                guard let goalID = transaction.savingsGoalID,
                      let occurrenceDate = transaction.savingsGoalOccurrenceDate else {
                    return nil
                }
                return SavingsGoalScheduler.marker(for: goalID, date: occurrenceDate, calendar: calendar)
            }
        )
        let horizon = calendar.date(byAdding: .year, value: 1, to: now) ?? now

        for goal in goals where !goal.isArchived && goal.automaticBooking && goal.contributionAmount > 0 {
            for occurrence in goal.occurrenceDates(through: horizon, calendar: calendar) {
                guard let reminderDate = reminderDate(for: occurrence, now: now, calendar: calendar),
                      !bookedMarkers.contains(SavingsGoalScheduler.marker(for: goal.id, date: occurrence, calendar: calendar)) else {
                    continue
                }

                let content = UNMutableNotificationContent()
                content.title = "Sparbeitrag steht an"
                content.body = goal.name.isEmpty
                    ? "Ein automatischer Sparbeitrag wird heute gebucht."
                    : "Der Sparbeitrag für \(goal.name) wird heute gebucht."
                content.sound = .default
                content.threadIdentifier = "savings"
                content.categoryIdentifier = "savings"
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate),
                    repeats: false
                )
                let identifier = "\(savingsPrefix)\(goal.id.uuidString)-\(dayKey(for: occurrence, calendar: calendar))"
                do {
                    try await center.add(
                        UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                    )
                } catch {
                    AppLogger.persistence.error(
                        "Sparbeitragsbenachrichtigung konnte nicht geplant werden: \(error)"
                    )
                }
            }
        }
    }

    private static func scheduleCompletedSavingsGoals(
        goals: [SavingsGoal],
        center: UNUserNotificationCenter
    ) async {
        for goal in goals where !goal.isArchived && goal.isCompleted {
            let key = "elyraBudget.notification.goal-completed.\(goal.id.uuidString)"
            guard !UserDefaults.standard.bool(forKey: key) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Sparziel erreicht"
            content.body = goal.name.isEmpty
                ? "Du hast dein Sparziel erreicht."
                : "Du hast dein Sparziel \(goal.name) erreicht."
            content.sound = .default
            content.threadIdentifier = "savings"
            content.categoryIdentifier = "savings"
            do {
                try await center.add(
                    UNNotificationRequest(
                        identifier: "\(goalPrefix)\(goal.id.uuidString)",
                        content: content,
                        trigger: immediateTrigger()
                    )
                )
                UserDefaults.standard.set(true, forKey: key)
            } catch {
                AppLogger.persistence.error(
                    "Sparziel-Erfolgsmeldung konnte nicht geplant werden: \(error)"
                )
            }
        }
    }

    private static func scheduleMonthlySummary(
        transactions: [Transaction],
        center: UNUserNotificationCenter,
        now: Date,
        calendar: Calendar
    ) async {
        guard calendar.component(.day, from: now) == 1,
              let previousMonth = calendar.date(byAdding: .month, value: -1, to: now),
              let interval = calendar.dateInterval(of: .month, for: previousMonth) else {
            return
        }

        let previousTransactions = transactions.filter { interval.contains($0.date) }
        guard !previousTransactions.isEmpty else { return }
        let monthKey = dayKey(for: interval.start, calendar: calendar)
        let key = "elyraBudget.notification.monthly-summary.\(monthKey)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let expenses = previousTransactions
            .filter { $0.type == .expense }
            .reduce(Decimal.zero) { $0 + $1.absoluteNotificationAmount }
        let income = previousTransactions
            .filter { $0.type == .income }
            .reduce(Decimal.zero) { $0 + $1.absoluteNotificationAmount }

        let content = UNMutableNotificationContent()
        content.title = "Dein Monatsüberblick"
        content.body = "Letzten Monat: Ausgaben \(expenses), Einnahmen \(income)."
        content.sound = .default
        content.threadIdentifier = "summary"
        content.categoryIdentifier = "summary"
        do {
            try await center.add(
                UNNotificationRequest(
                    identifier: "\(summaryPrefix)\(monthKey)",
                    content: content,
                    trigger: immediateTrigger()
                )
            )
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            AppLogger.persistence.error("Monatsüberblick konnte nicht geplant werden: \(error)")
        }
    }

    private static func scheduleForecastRisks(
        goals: [SavingsGoal],
        center: UNUserNotificationCenter,
        now: Date,
        calendar: Calendar
    ) async {
        for goal in goals where !goal.isArchived && !goal.isCompleted && goal.targetDate != nil {
            let forecast = SavingsGoalForecast.calculate(for: goal, asOf: now, calendar: calendar)
            guard forecast.isOnTrack == false else { continue }
            let targetKey = dayKey(for: goal.targetDate ?? now, calendar: calendar)
            let key = "elyraBudget.notification.forecast-risk.\(goal.id.uuidString).\(targetKey)"
            guard !UserDefaults.standard.bool(forKey: key) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Sparziel-Prognose prüfen"
            content.body = goal.name.isEmpty
                ? "Dein Sparziel wird voraussichtlich nicht rechtzeitig erreicht."
                : "\(goal.name) wird voraussichtlich nicht rechtzeitig erreicht."
            content.sound = .default
            content.threadIdentifier = "savings"
            do {
                try await center.add(
                    UNNotificationRequest(
                        identifier: "\(forecastPrefix)\(goal.id.uuidString)",
                        content: content,
                        trigger: immediateTrigger()
                    )
                )
                UserDefaults.standard.set(true, forKey: key)
            } catch {
                AppLogger.persistence.error("Sparziel-Prognose konnte nicht geplant werden: \(error)")
            }
        }
    }

    private static func scheduleOverdueFixedCosts(
        fixedCosts: [FixedCost],
        transactions: [Transaction],
        center: UNUserNotificationCenter,
        now: Date,
        calendar: Calendar
    ) async {
        let today = calendar.startOfDay(for: now)
        let pending = FixedCostScheduler.pendingManualBookings(
            fixedCosts: fixedCosts,
            transactions: transactions,
            through: now,
            calendar: calendar
        )

        for item in pending where item.dueDate < today && item.fixedCost.reminderEnabled {
            let dateKey = dayKey(for: item.dueDate, calendar: calendar)
            let key = "elyraBudget.notification.overdue-fixed-cost.\(item.fixedCost.id.uuidString).\(dateKey)"
            guard !UserDefaults.standard.bool(forKey: key) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Fixkosten überfällig"
            content.body = item.fixedCost.title.isEmpty
                ? "Eine manuelle Fixkostenbuchung ist noch offen."
                : "\(item.fixedCost.title) ist noch nicht gebucht."
            content.sound = .default
            content.threadIdentifier = "fixed-costs"
            do {
                try await center.add(
                    UNNotificationRequest(
                        identifier: "\(overduePrefix)\(item.fixedCost.id.uuidString)-\(dateKey)",
                        content: content,
                        trigger: immediateTrigger()
                    )
                )
                UserDefaults.standard.set(true, forKey: key)
            } catch {
                AppLogger.persistence.error("Überfällige Fixkostenmeldung konnte nicht geplant werden: \(error)")
            }
        }
    }

    private static func scheduleUnusualExpenses(
        transactions: [Transaction],
        center: UNUserNotificationCenter,
        now: Date,
        calendar: Calendar
    ) async {
        let currentMonth = calendar.dateInterval(of: .month, for: now)
        let historicalExpenses = transactions.filter {
            $0.type == .expense && $0.fixedCostID == nil && $0.savingsGoalID == nil
                && $0.date < (currentMonth?.start ?? now)
        }
        let average = historicalExpenses.isEmpty
            ? Decimal.zero
            : historicalExpenses.reduce(Decimal.zero) { $0 + $1.absoluteNotificationAmount }
                / Decimal(max(historicalExpenses.count, 1))
        let threshold = max(average * 2, 100)

        for transaction in transactions where transaction.type == .expense
            && transaction.fixedCostID == nil
            && transaction.savingsGoalID == nil
            && transaction.date.isInSameMonth(as: now, calendar: calendar)
            && transaction.absoluteNotificationAmount >= threshold {
            let transactionKey = transaction.createdAt.timeIntervalSinceReferenceDate
            let key = "elyraBudget.notification.unusual-expense.\(transactionKey)"
            guard !UserDefaults.standard.bool(forKey: key) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Ungewöhnlich hohe Ausgabe"
            content.body = "\(transaction.title) ist deutlich höher als deine üblichen Ausgaben."
            content.sound = .default
            content.threadIdentifier = "transactions"
            content.categoryIdentifier = "transactions"
            do {
                try await center.add(
                    UNNotificationRequest(
                        identifier: "\(unusualExpensePrefix)\(transactionKey)",
                        content: content,
                        trigger: immediateTrigger()
                    )
                )
                UserDefaults.standard.set(true, forKey: key)
            } catch {
                AppLogger.persistence.error("Ausgabenwarnung konnte nicht geplant werden: \(error)")
            }
        }
    }

    private static func scheduleDailyDigest(
        transactions: [Transaction],
        center: UNUserNotificationCenter,
        now: Date,
        calendar: Calendar
    ) async {
        let todayTransactions = transactions.filter { calendar.isDateInToday($0.date) }
        guard !todayTransactions.isEmpty else { return }

        let digestHour = 18
        var deliveryDate = calendar.date(bySettingHour: digestHour, minute: 0, second: 0, of: now) ?? now
        if deliveryDate <= now {
            deliveryDate = calendar.date(byAdding: .day, value: 1, to: deliveryDate) ?? deliveryDate
        }

        let expenses = todayTransactions
            .filter { $0.type == .expense }
            .reduce(Decimal.zero) { $0 + $1.absoluteNotificationAmount }
        let content = UNMutableNotificationContent()
        content.title = "Dein Tagesüberblick"
        content.body = "Heute: \(todayTransactions.count) Buchungen, Ausgaben \(expenses)."
        content.sound = .default
        content.threadIdentifier = "summary"
        content.categoryIdentifier = "summary"
        let identifier = dailyDigestIdentifier
        do {
            try await center.add(
                UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(
                        dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: deliveryDate),
                        repeats: false
                    )
                )
            )
        } catch {
            AppLogger.persistence.error(
                "Tagesüberblick konnte nicht geplant werden: \(error)"
            )
        }
    }

    private static func configureQuietHours(using settings: UserSettings?) {
        guard let settings else { return }
        let defaults = UserDefaults.standard
        defaults.set(settings.notificationQuietHoursEnabled, forKey: "elyraBudget.notifications.quiet.enabled")
        defaults.set(settings.notificationQuietHoursStart, forKey: "elyraBudget.notifications.quiet.start")
        defaults.set(settings.notificationQuietHoursEnd, forKey: "elyraBudget.notifications.quiet.end")
    }

    private static func immediateTrigger(
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> UNNotificationTrigger {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "elyraBudget.notifications.quiet.enabled") as? Bool ?? true else {
            return UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        }

        let start = defaults.integer(forKey: "elyraBudget.notifications.quiet.start")
        let end = defaults.integer(forKey: "elyraBudget.notifications.quiet.end")
        let hour = calendar.component(.hour, from: now)
        let isQuiet = start == end
            ? false
            : start > end
                ? hour >= start || hour < end
                : hour >= start && hour < end
        guard isQuiet,
              let quietEnd = calendar.date(bySettingHour: end, minute: 0, second: 0, of: now) else {
            return UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        }

        let deliveryDate = quietEnd > now
            ? quietEnd
            : calendar.date(byAdding: .day, value: 1, to: quietEnd) ?? quietEnd
        return UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: deliveryDate),
            repeats: false
        )
    }

    private static func reminderDate(for occurrence: Date, now: Date, calendar: Calendar) -> Date? {
        guard let date = calendar.date(bySettingHour: reminderHour, minute: 0, second: 0, of: occurrence) else {
            return nil
        }
        return date > now ? date : nil
    }

    private static func pendingNotificationRequests(
        from center: UNUserNotificationCenter
    ) async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

private extension Transaction {
    var absoluteNotificationAmount: Decimal {
        amount < 0 ? -amount : amount
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
