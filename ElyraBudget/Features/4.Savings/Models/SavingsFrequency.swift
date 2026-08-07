import Foundation

enum SavingsFrequency: String, CaseIterable, Codable, Identifiable {
    case daily
    case weekly
    case monthly
    case quarterly
    case halfYearly
    case yearly

    var id: Self { self }

    var title: String {
        switch self {
        case .daily: "Täglich"
        case .weekly: "Wöchentlich"
        case .monthly: "Monatlich"
        case .quarterly: "Vierteljährlich"
        case .halfYearly: "Halbjährlich"
        case .yearly: "Jährlich"
        }
    }

    var months: Int? {
        switch self {
        case .monthly: 1
        case .quarterly: 3
        case .halfYearly: 6
        case .yearly: 12
        case .daily, .weekly: nil
        }
    }
}
