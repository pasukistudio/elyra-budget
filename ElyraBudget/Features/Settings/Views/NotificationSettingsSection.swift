import SwiftUI

struct NotificationSettingsSection: View {
    let profile: UserSettings?
    let saveSettings: () -> Void
    let requestPermission: (Bool) -> Void

    var body: some View {
        Section("Benachrichtigungen") {
            if let profile {
                notificationToggle("Budgetwarnungen und Monatsstart", value: \.budgetNotificationsEnabled, profile: profile)
                notificationToggle("Sparbeiträge", value: \.savingsContributionNotificationsEnabled, profile: profile)
                notificationToggle("iCloud-Synchronisierungsfehler", value: \.syncErrorNotificationsEnabled, profile: profile)
                notificationToggle("Sparziel erreicht", value: \.savingsGoalCompletionNotificationsEnabled, profile: profile)
                notificationToggle("Fehlgeschlagene automatische Buchungen", value: \.automaticBookingFailureNotificationsEnabled, profile: profile)
                notificationToggle("Monatlicher Finanzüberblick", value: \.monthlySummaryNotificationsEnabled, profile: profile)
                notificationToggle("Sparziel-Prognose", value: \.forecastRiskNotificationsEnabled, profile: profile)
                notificationToggle("Überfällige Fixkosten", value: \.overdueFixedCostNotificationsEnabled, profile: profile)
                notificationToggle("iCloud wieder synchronisiert", value: \.syncRecoveryNotificationsEnabled, profile: profile)
                notificationToggle("Ungewöhnlich hohe Ausgaben", value: \.unusualExpenseNotificationsEnabled, profile: profile)
                notificationToggle("Tägliche Zusammenfassung", value: \.dailyDigestNotificationsEnabled, profile: profile)

                Toggle(
                    "Ruhezeiten",
                    isOn: binding(for: \.notificationQuietHoursEnabled, profile: profile)
                )

                if profile.notificationQuietHoursEnabled {
                    Stepper(
                        "Ab \(profile.notificationQuietHoursStart):00 Uhr",
                        value: binding(for: \.notificationQuietHoursStart, profile: profile, range: 0 ... 23),
                        in: 0 ... 23
                    )
                    Stepper(
                        "Bis \(profile.notificationQuietHoursEnd):00 Uhr",
                        value: binding(for: \.notificationQuietHoursEnd, profile: profile, range: 0 ... 23),
                        in: 0 ... 23
                    )
                }
            }

            Text("Fixkosten-Erinnerungen werden direkt bei der jeweiligen Fixkostenregel gesteuert.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func notificationToggle(
        _ title: String,
        value keyPath: ReferenceWritableKeyPath<UserSettings, Bool>,
        profile: UserSettings
    ) -> some View {
        Toggle(
            title,
            isOn: binding(for: keyPath, profile: profile, requestsPermission: true)
        )
    }

    private func binding(
        for keyPath: ReferenceWritableKeyPath<UserSettings, Bool>,
        profile: UserSettings,
        requestsPermission: Bool = false
    ) -> Binding<Bool> {
        Binding(
            get: { profile[keyPath: keyPath] },
            set: { value in
                profile[keyPath: keyPath] = value
                profile.updatedAt = .now
                saveSettings()
                if requestsPermission {
                    requestPermission(value)
                }
            }
        )
    }

    private func binding(
        for keyPath: ReferenceWritableKeyPath<UserSettings, Int>,
        profile: UserSettings,
        range: ClosedRange<Int>
    ) -> Binding<Int> {
        Binding(
            get: { profile[keyPath: keyPath] },
            set: { value in
                profile[keyPath: keyPath] = min(max(value, range.lowerBound), range.upperBound)
                profile.updatedAt = .now
                saveSettings()
            }
        )
    }
}
