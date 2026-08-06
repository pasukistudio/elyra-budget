//
//  TransactionType.swift
//  ElyraBudget
//
//  Created by Pascal Smigielski on 06.08.26.
//


import Foundation

enum TransactionType:
    String,
    CaseIterable,
    Identifiable,
    Codable {

    case expense
    case income
    case refund

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .expense:
            return "Ausgabe"

        case .income:
            return "Einnahme"

        case .refund:
            return "Rückerstattung"
        }
    }

    var systemImage: String {
        switch self {
        case .expense:
            return "arrow.up.right"

        case .income:
            return "arrow.down.left"

        case .refund:
            return "arrow.uturn.backward"
        }
    }
}
