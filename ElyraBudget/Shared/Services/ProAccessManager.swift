//
//  ProAccessManager.swift
//  ElyraBudget
//
//  Created by Pascal Smigielski on 05.08.26.
//

import Foundation
import Observation
import StoreKit

@Observable
final class ProAccessManager {
    // MARK: - Pro-Status

    /// Gibt an, ob Elyra Budget Pro freigeschaltet ist.
    var hasPro: Bool

    #if os(macOS)
    private static let macTrialStartKey = "elyraBudget.macOSProTrialStartedAt"
    private static let macTrialDuration: TimeInterval = 7 * 24 * 60 * 60

    /// Der Testzeitraum gilt nur für die macOS-App. Der Startzeitpunkt wird
    /// gespeichert, damit ein Neustart die Testphase nicht zurücksetzt.
    private(set) var macTrialStartDate: Date?

    var isMacTrialActive: Bool {
        guard let macTrialStartDate else { return false }
        return Date().timeIntervalSince(macTrialStartDate) < Self.macTrialDuration
    }

    var macTrialDaysRemaining: Int {
        guard let macTrialStartDate else { return 0 }
        let remaining = Self.macTrialDuration - Date().timeIntervalSince(macTrialStartDate)
        guard remaining > 0 else { return 0 }
        return max(1, Int(ceil(remaining / (24 * 60 * 60))))
    }

    /// Nach Ablauf der macOS-Testphase ist die gesamte App nur noch mit Pro
    /// nutzbar. Auf iOS und iPadOS gibt es diese globale Sperre nicht.
    var requiresMacPro: Bool {
        !hasPro && !isMacTrialActive
    }
    #endif

    #if DEBUG
    private static let testingProKey = "elyraBudget.debug.proEnabled"
    #endif

    init() {
        #if DEBUG
        hasPro = UserDefaults.standard.bool(forKey: Self.testingProKey)
        #else
        hasPro = false
        #endif

        #if os(macOS)
        if let storedDate = UserDefaults.standard.object(forKey: Self.macTrialStartKey) as? Date {
            macTrialStartDate = storedDate
        } else {
            let startDate = Date()
            macTrialStartDate = startDate
            UserDefaults.standard.set(startDate, forKey: Self.macTrialStartKey)
        }
        #endif
    }

    static let productID = "de.pascal.ElyraBudget.pro"
    private(set) var product: Product?
    private(set) var isLoadingProduct = false
    private(set) var isRestoringPurchases = false
    var purchaseError: String?

    // MARK: - Testfunktionen

    /// Aktiviert Pro für Entwicklung und Previews.
    func enableProForTesting() {
        hasPro = true
        #if DEBUG
        UserDefaults.standard.set(true, forKey: Self.testingProKey)
        #endif
    }

    /// Deaktiviert Pro für Entwicklung und Previews.
    func disableProForTesting() {
        hasPro = false
        #if DEBUG
        UserDefaults.standard.set(false, forKey: Self.testingProKey)
        #endif
    }

    @MainActor
    func loadProduct() async {
        guard product == nil, !isLoadingProduct else { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }

        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    @MainActor
    func refreshEntitlement() async {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: Self.testingProKey) {
            hasPro = true
            return
        }
        #endif

        // Recalculate the entitlement from StoreKit instead of keeping a stale
        // in-memory value after a restore, revocation, or account change.
        hasPro = false

        for await result in StoreKit.Transaction.currentEntitlements(for: Self.productID) {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                hasPro = true
                return
            }
        }
    }

    @MainActor
    func listenForTransactionUpdates() async {
        for await result in StoreKit.Transaction.updates {
            guard case .verified(let transaction) = result else { continue }

            if transaction.productID == Self.productID {
                #if DEBUG
                if UserDefaults.standard.bool(forKey: Self.testingProKey) {
                    hasPro = true
                } else {
                    hasPro = transaction.revocationDate == nil
                }
                #else
                hasPro = transaction.revocationDate == nil
                #endif
            }

            await transaction.finish()
        }
    }

    @MainActor
    func purchase() async {
        guard let product else {
            purchaseError = "Das Pro-Angebot ist derzeit nicht verfügbar."
            return
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                hasPro = true
                await transaction.finish()
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Der Kauf wartet noch auf Bestätigung."
            @unknown default:
                purchaseError = "Der Kauf konnte nicht abgeschlossen werden."
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    @MainActor
    func restorePurchases() async {
        guard !isRestoringPurchases else { return }
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }

        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw StoreKitError.failedVerification
        }
    }
}

private enum StoreKitError: Error {
    case failedVerification
}
