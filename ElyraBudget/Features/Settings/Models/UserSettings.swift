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
        currencyRawValue: String = AppCurrency.eur.rawValue
    ) {
        self.name = name
        self.appearanceRawValue = appearanceRawValue
        self.accentColorRawValue = accentColorRawValue
        self.customAccentHex = customAccentHex
        self.currencyRawValue = currencyRawValue
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
