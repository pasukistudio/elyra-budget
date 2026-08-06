import SwiftUI

enum AppAccentColor: String, CaseIterable, Identifiable {

    // MARK: - Farben

    case red
    case orange
    case green
    case teal
    case blue
    case indigo
    case purple
    case pink
    case custom

    // MARK: - Identifiable

    var id: Self {
        self
    }

    // MARK: - Anzeigename

    var title: LocalizedStringResource {
        switch self {
        case .custom:
            return "Eigene Farbe"

        default:
            return preset?.title ?? ""
        }
    }

    // MARK: - Farbvorlage

    var preset: ColorPreset? {
        switch self {
        case .custom:
            return nil

        case .red:
            return .red

        case .orange:
            return .orange

        case .green:
            return .green

        case .teal:
            return .teal

        case .blue:
            return .blue

        case .indigo:
            return .indigo

        case .purple:
            return .purple

        case .pink:
            return .pink

        }
    }

    // MARK: - SwiftUI-Farbe

    var color: Color? {
        preset?.color
    }

    // MARK: - Pro-Zugriff

    var isProOnly: Bool {
        self == .custom
    }
}
