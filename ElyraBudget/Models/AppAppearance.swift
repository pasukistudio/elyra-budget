//
//  AppAppearance.swift
//  ElyraBudget
//
//  Created by Pascal Smigielski on 04.08.26.
//

import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    // MARK: - Erscheinungsbilder

    case system
    case light
    case dark

    // MARK: - Identifiable

    var id: Self {
        self
    }

    // MARK: - Anzeigename

    var title: LocalizedStringResource {
        switch self {
        case .system:
            return "System"

        case .light:
            return "Hell"

        case .dark:
            return "Dunkel"
        }
    }

    // MARK: - Symbol

    var icon: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"

        case .light:
            return "sun.max"

        case .dark:
            return "moon"
        }
    }

    // MARK: - Farbschema

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil

        case .light:
            return .light

        case .dark:
            return .dark
        }
    }
}
