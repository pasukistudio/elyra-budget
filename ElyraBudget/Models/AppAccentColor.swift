import SwiftUI

enum AppAccentColor: String, CaseIterable, Identifiable {

    // MARK: - Farben

    case system
    case blue
    case green
    case orange
    case red
    case purple
    case pink
    case teal
    case custom

    // MARK: - Identifiable

    var id: Self {
        self
    }

    // MARK: - Anzeigename

    var title: LocalizedStringResource {
        switch self {
        case .system:
            return "System"

        case .blue:
            return "Blau"

        case .green:
            return "Grün"

        case .orange:
            return "Orange"

        case .red:
            return "Rot"

        case .purple:
            return "Lila"

        case .pink:
            return "Rosa"

        case .teal:
            return "Türkis"

        case .custom:
            return "Eigene Farbe"
        }
    }

    // MARK: - SwiftUI-Farbe

    var color: Color? {
        switch self {
        case .system, .custom:
            return nil

        case .blue:
            return .blue

        case .green:
            return .green

        case .orange:
            return .orange

        case .red:
            return .red

        case .purple:
            return .purple

        case .pink:
            return .pink

        case .teal:
            return .teal
        }
    }

    // MARK: - Pro-Zugriff

    var isProOnly: Bool {
        self == .custom
    }
}
