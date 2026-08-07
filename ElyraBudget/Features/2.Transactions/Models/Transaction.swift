//
//  Transaction.swift
//  ElyraBudget
//
//  Created by Pascal Smigielski on 06.08.26.
//

import Foundation
import SwiftData

@Model
final class Transaction {
    // MARK: - Grunddaten

    var title: String = ""
    var amount: Decimal = 0
    var date: Date = Date()
    var note: String = ""

    // MARK: - Typ

    var typeRawValue: String =
        TransactionType.expense.rawValue

    // MARK: - Budget-Zuordnung

    var budget: Budget?

    // MARK: - Fixkosten-Zuordnung

    /// Identifies transactions generated from a fixed cost.
    var fixedCostID: UUID?
    var fixedCostOccurrenceDate: Date?

    // MARK: - Zeitstempel

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: - Initialisierung

    init(
        title: String = "",
        amount: Decimal = 0,
        date: Date = Date(),
        note: String = "",
        type: TransactionType = .expense,
        budget: Budget? = nil
    ) {
        self.title = title
        self.amount = amount
        self.date = date
        self.note = note
        self.typeRawValue = type.rawValue
        self.budget = budget
        self.fixedCostID = nil
        self.fixedCostOccurrenceDate = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: - Berechnete Werte

    var type: TransactionType {
        get {
            TransactionType(
                rawValue: typeRawValue
            ) ?? .expense
        }
        set {
            typeRawValue = newValue.rawValue
        }
    }

    var signedAmount: Decimal {
        switch type {
        case .expense:
            return -absoluteAmount

        case .income,
             .refund:
            return absoluteAmount
        }
    }

    var budgetImpact: Decimal {
        switch type {
        case .expense:
            return absoluteAmount

        case .refund:
            return -absoluteAmount

        case .income:
            return 0
        }
    }

    private var absoluteAmount: Decimal {
        amount < 0
            ? -amount
            : amount
    }
}
