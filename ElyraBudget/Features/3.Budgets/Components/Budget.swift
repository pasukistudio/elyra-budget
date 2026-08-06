import Foundation
import SwiftData

@Model
final class Budget {
    // MARK: - Grunddaten

    var name: String = ""

    // MARK: - Darstellung

    var iconName: String = "cart.fill"
    var iconColorHex: String = "#FF9500"

    // MARK: - Budgeteinstellungen

    /// `0` bedeutet: Das Budget besitzt kein Limit.
    var limit: Decimal = 0

    var includesFixedCosts: Bool = true

    // MARK: - Organisation

    var sortOrder: Int = 0
    var isArchived: Bool = false

    // MARK: - Zeitstempel

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: - Initialisierung

    init(
        name: String = "",
        iconName: String = "cart.fill",
        iconColorHex: String = "#FF9500",
        limit: Decimal = 0,
        includesFixedCosts: Bool = true,
        sortOrder: Int = 0,
        isArchived: Bool = false
    ) {
        self.name = name
        self.iconName = iconName
        self.iconColorHex = iconColorHex
        self.limit = limit
        self.includesFixedCosts = includesFixedCosts
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
