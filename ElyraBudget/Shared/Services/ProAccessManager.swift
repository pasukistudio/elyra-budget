//
//  ProAccessManager.swift
//  ElyraBudget
//
//  Created by Pascal Smigielski on 05.08.26.
//

import Foundation
import Observation
import StoreKit

enum ProProductPlan: String, CaseIterable, Identifiable {
    case monthly
    case yearly
    case lifetime

    var id: String { rawValue }

    var productID: String {
        switch self {
        case .monthly: "de.pasukistudio.elyrabudget.pro.monthly"
        case .yearly: "de.pasukistudio.elyrabudget.pro.yearly"
        case .lifetime: "de.pasukistudio.elyrabudget.pro.lifetime.v1"
        }
    }

    var title: String {
        switch self {
        case .monthly: "Monatlich"
        case .yearly: "Jährlich"
        case .lifetime: "Für immer"
        }
    }

    var subtitle: String {
        switch self {
        case .monthly: "Flexibel monatlich kündbar"
        case .yearly: "Beste Wahl – günstiger als monatlich"
        case .lifetime: "Einmal zahlen, dauerhaft nutzen"
        }
    }
}

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
        #if INTERNAL_PRO
        hasPro = true
        #else
        #if DEBUG
        hasPro = UserDefaults.standard.bool(forKey: Self.testingProKey)
        #else
        hasPro = false
        #endif
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

    static let productIDs = ProProductPlan.allCases.map(\.productID)
    private(set) var products: [String: Product] = [:]
    var selectedPlan: ProProductPlan = .yearly
    private(set) var isLoadingProduct = false
    private(set) var isRestoringPurchases = false
    var purchaseError: String?

    var selectedProduct: Product? {
        products[selectedPlan.productID]
    }

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
        guard products.isEmpty, !isLoadingProduct else { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }

        do {
            let loadedProducts = try await Product.products(for: Self.productIDs)
            let productsByID = Dictionary(
                uniqueKeysWithValues: loadedProducts.map { ($0.id, $0) }
            )
            products = productsByID

            if productsByID[selectedPlan.productID] == nil,
               let fallbackPlan = ProProductPlan.allCases.first(where: {
                   productsByID[$0.productID] != nil
               }) {
                selectedPlan = fallbackPlan
            }

            if productsByID.isEmpty {
                purchaseError = "Die Pro-Angebote sind derzeit nicht verfügbar. Bitte versuche es später erneut."
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    @MainActor
    func refreshEntitlement() async {
        #if INTERNAL_PRO
        hasPro = true
        return
        #else
        #if DEBUG
        if UserDefaults.standard.bool(forKey: Self.testingProKey) {
            hasPro = true
            return
        }
        #endif

        // Recalculate the entitlement from StoreKit instead of keeping a stale
        // in-memory value after a restore, revocation, or account change.
        hasPro = false

        for productID in Self.productIDs {
            for await result in StoreKit.Transaction.currentEntitlements(for: productID) {
                guard case .verified(let transaction) = result else { continue }
                if transaction.productID == productID,
                   transaction.revocationDate == nil {
                    hasPro = true
                    return
                }
            }
        }
        #endif
    }

    @MainActor
    func listenForTransactionUpdates() async {
        for await result in StoreKit.Transaction.updates {
            guard case .verified(let transaction) = result else { continue }

            if Self.productIDs.contains(transaction.productID) {
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
    func purchase(plan: ProProductPlan? = nil) async {
        let plan = plan ?? selectedPlan
        guard let product = products[plan.productID] else {
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
