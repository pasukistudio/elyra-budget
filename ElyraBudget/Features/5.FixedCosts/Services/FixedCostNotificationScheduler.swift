import Foundation
import OSLog
import UserNotifications

enum FixedCostNotificationScheduler {
    private static let identifierPrefix = "fixed-cost-due-"
    private static let reminderHour = 9
    private static let maximumScheduledNotifications = 60

    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                AppLogger.persistence.error(
                    "Berechtigung für Fixkosten-Erinnerungen konnte nicht angefragt werden: \(error)"
                )
                return false
            }
        case .denied, .ephemeral:
            return false
        @unknown default:
            return false
        }
    }

    static func reschedule(
        fixedCosts: [FixedCost],
        transactions: [Transaction],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) async {
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await pendingNotificationRequests(from: center)
        let oldIdentifiers = pendingRequests
            .map { $0.identifier }
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: oldIdentifiers)

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional else {
            return
        }

        let bookedMarkers = Set(
            transactions.compactMap { transaction -> String? in
                guard let fixedCostID = transaction.fixedCostID,
                      let occurrenceDate = transaction.fixedCostOccurrenceDate else {
                    return nil
                }
                return FixedCostScheduler.marker(
                    for: fixedCostID,
                    date: occurrenceDate,
                    calendar: calendar
                )
            }
        )

        let horizon = calendar.date(
            byAdding: .year,
            value: 1,
            to: now
        ) ?? now
        var requests: [(date: Date, request: UNNotificationRequest)] = []

        for fixedCost in fixedCosts {
            guard !fixedCost.automaticBooking,
                  fixedCost.reminderEnabled,
                  fixedCost.isActive(on: now, calendar: calendar) else {
                continue
            }

            let occurrences = fixedCost.occurrenceDates(
                from: now,
                through: horizon,
                calendar: calendar
            )

            for occurrence in occurrences {
                let marker = FixedCostScheduler.marker(
                    for: fixedCost.id,
                    date: occurrence,
                    calendar: calendar
                )
                guard !bookedMarkers.contains(marker),
                      let notificationDate = reminderDate(
                        for: occurrence,
                        now: now,
                        calendar: calendar
                      ) else {
                    continue
                }

                let content = UNMutableNotificationContent()
                content.title = "Fixkosten fällig"
                content.body = fixedCost.title.isEmpty
                    ? "Eine manuelle Fixkostenbuchung ist heute fällig."
                    : "\(fixedCost.title) ist heute fällig."
                content.sound = .default
                content.threadIdentifier = "fixed-costs"
                content.categoryIdentifier = "fixed-costs"

                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: calendar.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: notificationDate
                    ),
                    repeats: false
                )
                let identifier = "\(identifierPrefix)\(fixedCost.id.uuidString)-\(dayKey(for: occurrence, calendar: calendar))"
                let request = UNNotificationRequest(
                        identifier: identifier,
                        content: content,
                        trigger: trigger
                    )
                requests.append((date: notificationDate, request: request))
            }
        }

        for entry in requests.sorted(by: { $0.date < $1.date }).prefix(maximumScheduledNotifications) {
            do {
                try await center.add(entry.request)
            } catch {
                AppLogger.persistence.error(
                    "Fixkosten-Erinnerung konnte nicht geplant werden: \(error)"
                )
            }
        }
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

    static func reminderDate(
        for occurrence: Date,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        guard let date = calendar.date(
            bySettingHour: reminderHour,
            minute: 0,
            second: 0,
            of: occurrence
        ) else {
            return nil
        }

        return date > now ? date : nil
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}
