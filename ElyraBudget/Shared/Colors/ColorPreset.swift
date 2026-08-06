//
//  ColorPreset.swift
//  ElyraBudget
//
//  Created by Pascal Smigielski on 06.08.26.
//

import SwiftUI

enum ColorPreset: String, CaseIterable, Identifiable {

    // MARK: - Farben

    case red
    case orange
    case green
    case teal
    case cyan
    case blue
    case indigo
    case purple
    case pink
    case gray

    // MARK: - Identifiable

    var id: Self {
        self
    }

    // MARK: - Anzeigename

    var title: LocalizedStringResource {
        switch self {
        case .red:
            return "Rot"

        case .orange:
            return "Orange"

        case .green:
            return "Grün"

        case .teal:
            return "Türkis"

        case .cyan:
            return "Cyan"

        case .blue:
            return "Blau"

        case .indigo:
            return "Indigo"

        case .purple:
            return "Lila"

        case .pink:
            return "Rosa"

        case .gray:
            return "Grau"
        }
    }

    // MARK: - Hex-Wert

    var hex: String {
        switch self {
        case .red:
            return "#FF3B30"

        case .orange:
            return "#FF9500"

        case .green:
            return "#34C759"

        case .teal:
            return "#00C7BE"

        case .cyan:
            return "#32ADE6"

        case .blue:
            return "#007AFF"

        case .indigo:
            return "#5856D6"

        case .purple:
            return "#AF52DE"

        case .pink:
            return "#FF2D55"

        case .gray:
            return "#8E8E93"
        }
    }

    // MARK: - SwiftUI-Farbe

    var color: Color {
        Color(hexString: hex)
    }
}
