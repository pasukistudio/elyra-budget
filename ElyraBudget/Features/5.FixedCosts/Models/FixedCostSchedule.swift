import Foundation

enum FixedCostSchedule: String, CaseIterable, Codable, Identifiable {
    case fixedDay
    case firstDayOfMonth
    case middleOfMonth
    case lastDayOfMonth

    var id: Self { self }

    var title: String {
        switch self {
        case .fixedDay: "Festes Datum"
        case .firstDayOfMonth: "Erster Tag des Monats"
        case .middleOfMonth: "Mitte des Monats"
        case .lastDayOfMonth: "Letzter Tag des Monats"
        }
    }
}
