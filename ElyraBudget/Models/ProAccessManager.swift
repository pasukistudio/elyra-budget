//
//  ProAccessManager.swift
//  ElyraBudget
//
//  Created by Pascal Smigielski on 05.08.26.
//

import Foundation
import Observation

@Observable
final class ProAccessManager {

    // MARK: - Pro-Status

    /// Gibt an, ob Elyra Budget Pro freigeschaltet ist.
    var hasPro: Bool = false

    // MARK: - Testfunktionen

    /// Aktiviert Pro für Entwicklung und Previews.
    func enableProForTesting() {
        hasPro = true
    }

    /// Deaktiviert Pro für Entwicklung und Previews.
    func disableProForTesting() {
        hasPro = false
    }
}
