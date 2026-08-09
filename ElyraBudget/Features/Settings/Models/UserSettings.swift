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
        orangeBudgetThreshold: Int = 100
    ) {
        self.name = name
        self.appearanceRawValue = appearanceRawValue
        self.accentColorRawValue = accentColorRawValue
        self.customAccentHex = customAccentHex
        self.currencyRawValue = currencyRawValue
        self.greenBudgetThreshold = greenBudgetThreshold
        self.orangeBudgetThreshold = orangeBudgetThreshold
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
