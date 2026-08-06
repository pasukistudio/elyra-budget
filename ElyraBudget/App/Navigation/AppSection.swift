//
//  SidebarSection.swift
//  ElyraBudget
//
//  Created by Pascal Smigielski on 04.08.26.
//

import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    // MARK: - Bereiche

    case overview
    case transactions
    case budgets
    case savings
    case fixcosts

    // MARK: - Identifiable

    var id: Self {
        self
    }

    // MARK: - Anzeigename

    var title: LocalizedStringResource {
        switch self {
        case .overview:
            return "Übersicht"

        case .transactions:
            return "Buchungen"

        case .budgets:
            return "Budgets"

        case .savings:
            return "Sparen"

        case .fixcosts:
            return "Fixkosten"
        }
    }

    // MARK: - Symbol

    var icon: String {
        switch self {
        case .overview:
            return "house"

        case .transactions:
            return "list.bullet.rectangle"

        case .budgets:
            return "chart.pie"

        case .savings:
            return "banknote"

        case .fixcosts:
            return "calendar.badge.clock"
        }
    }
}
