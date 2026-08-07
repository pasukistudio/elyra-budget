import Foundation

enum SavingsGoalType: String, CaseIterable, Identifiable {
    case goal
    case reserve

    var id: String { rawValue }

    var title: String {
        switch self {
        case .goal: "Sparziel"
        case .reserve: "Freie Rücklage"
        }
    }

    var creationTitle: String {
        switch self {
        case .goal: "Neues Sparziel"
        case .reserve: "Neue freie Rücklage"
        }
    }

    var editTitle: String {
        switch self {
        case .goal: "Sparziel bearbeiten"
        case .reserve: "Freie Rücklage bearbeiten"
        }
    }
}
