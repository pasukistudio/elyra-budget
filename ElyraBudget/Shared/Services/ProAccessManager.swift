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
    var hasPro: Bool = false

    static let productID = "de.pascal.ElyraBudget.pro"
    private(set) var product: Product?
    private(set) var isLoadingProduct = false
    private(set) var isRestoringPurchases = false
    var purchaseError: String?

    // MARK: - Testfunktionen

    /// Aktiviert Pro für Entwicklung und Previews.
    func enableProForTesting() {
        hasPro = true
    }

    /// Deaktiviert Pro für Entwicklung und Previews.
    func disableProForTesting() {
        hasPro = false
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
                hasPro = transaction.revocationDate == nil
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
