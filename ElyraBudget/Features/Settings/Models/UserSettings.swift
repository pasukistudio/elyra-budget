import Foundation
import SwiftData

@Model
final class UserSettings {

    // MARK: - Profil

    var name: String = ""

    // MARK: - Erscheinungsbild

    var appearanceRawValue: String =
        AppAppearance.system.rawValue

    var accentColorRawValue: String =
        AppAccentColor.blue.rawValue

    var customAccentHex: String = "#007AFF"

    var currencyRawValue: String = AppCurrency.eur.rawValue

    // MARK: - Budgetstatus

    /// Upper utilization percentage for the green budget indicator.
    var greenBudgetThreshold: Int = 70

    /// Upper utilization percentage for the orange budget indicator.
    /// Values above this threshold are shown in red.
    var orangeBudgetThreshold: Int = 100

    // MARK: - Benachrichtigungen

    var budgetNotificationsEnabled: Bool = true
    var savingsContributionNotificationsEnabled: Bool = false
    var syncErrorNotificationsEnabled: Bool = true
    var savingsGoalCompletionNotificationsEnabled: Bool = true
    var automaticBookingFailureNotificationsEnabled: Bool = true
    var monthlySummaryNotificationsEnabled: Bool = false
    var forecastRiskNotificationsEnabled: Bool = false
    var overdueFixedCostNotificationsEnabled: Bool = true
    var syncRecoveryNotificationsEnabled: Bool = false
    var feedbackStatusNotificationsEnabled: Bool = false
    var unusualExpenseNotificationsEnabled: Bool = false
    var dailyDigestNotificationsEnabled: Bool = false
    var appLockEnabled: Bool = false
    var notificationQuietHoursEnabled: Bool = true
    var notificationQuietHoursStart: Int = 22
    var notificationQuietHoursEnd: Int = 7

    // MARK: - Zeitstempel

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: - Initialisierung

    init(
        name: String = "",
        appearanceRawValue: String =
            AppAppearance.system.rawValue,
        accentColorRawValue: String =
            AppAccentColor.blue.rawValue,
        customAccentHex: String = "#007AFF",
        currencyRawValue: String = AppCurrency.eur.rawValue,
        greenBudgetThreshold: Int = 70,
        orangeBudgetThreshold: Int = 100,
        budgetNotificationsEnabled: Bool = true,
        savingsContributionNotificationsEnabled: Bool = false,
        syncErrorNotificationsEnabled: Bool = true,
        savingsGoalCompletionNotificationsEnabled: Bool = true,
        automaticBookingFailureNotificationsEnabled: Bool = true,
        monthlySummaryNotificationsEnabled: Bool = false,
        forecastRiskNotificationsEnabled: Bool = false,
        overdueFixedCostNotificationsEnabled: Bool = true,
        syncRecoveryNotificationsEnabled: Bool = false,
        feedbackStatusNotificationsEnabled: Bool = false,
        unusualExpenseNotificationsEnabled: Bool = false,
        dailyDigestNotificationsEnabled: Bool = false,
        appLockEnabled: Bool = false,
        notificationQuietHoursEnabled: Bool = true,
        notificationQuietHoursStart: Int = 22,
        notificationQuietHoursEnd: Int = 7
    ) {
        self.name = name
        self.appearanceRawValue = appearanceRawValue
        self.accentColorRawValue = accentColorRawValue
        self.customAccentHex = customAccentHex
        self.currencyRawValue = currencyRawValue
        self.greenBudgetThreshold = greenBudgetThreshold
        self.orangeBudgetThreshold = orangeBudgetThreshold
        self.budgetNotificationsEnabled = budgetNotificationsEnabled
        self.savingsContributionNotificationsEnabled = savingsContributionNotificationsEnabled
        self.syncErrorNotificationsEnabled = syncErrorNotificationsEnabled
        self.savingsGoalCompletionNotificationsEnabled = savingsGoalCompletionNotificationsEnabled
        self.automaticBookingFailureNotificationsEnabled = automaticBookingFailureNotificationsEnabled
        self.monthlySummaryNotificationsEnabled = monthlySummaryNotificationsEnabled
        self.forecastRiskNotificationsEnabled = forecastRiskNotificationsEnabled
        self.overdueFixedCostNotificationsEnabled = overdueFixedCostNotificationsEnabled
        self.syncRecoveryNotificationsEnabled = syncRecoveryNotificationsEnabled
        self.feedbackStatusNotificationsEnabled = feedbackStatusNotificationsEnabled
        self.unusualExpenseNotificationsEnabled = unusualExpenseNotificationsEnabled
        self.dailyDigestNotificationsEnabled = dailyDigestNotificationsEnabled
        self.appLockEnabled = appLockEnabled
        self.notificationQuietHoursEnabled = notificationQuietHoursEnabled
        self.notificationQuietHoursStart = notificationQuietHoursStart
        self.notificationQuietHoursEnd = notificationQuietHoursEnd
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
