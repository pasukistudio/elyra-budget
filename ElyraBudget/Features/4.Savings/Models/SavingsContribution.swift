import Foundation
import SwiftData

@Model
final class SavingsContribution {
    var id: UUID = UUID()
    var amount: Decimal = 0
    var date: Date = Date()
    var note: String = ""
    var automatic: Bool = false
    var occurrenceDate: Date?
    var goal: SavingsGoal?

    init(
        amount: Decimal,
        date: Date = .now,
        note: String = "",
        automatic: Bool = false,
        occurrenceDate: Date? = nil,
        goal: SavingsGoal? = nil
    ) {
        self.id = UUID()
        self.amount = amount
        self.date = date
        self.note = note
        self.automatic = automatic
        self.occurrenceDate = occurrenceDate
        self.goal = goal
    }
}
