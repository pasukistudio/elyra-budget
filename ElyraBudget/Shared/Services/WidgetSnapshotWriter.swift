import Foundation
import os
import SwiftData

#if canImport(WidgetKit)
import WidgetKit
#endif

struct ElyraWidgetSnapshot: Codable {
    let groupName: String
    let spent: Decimal
    let budget: Decimal
    let savingsProgress: Double
    let currencyCode: String
    let updatedAt: Date
}

@MainActor
enum WidgetSnapshotWriter {
    static let appGroup = "group.de.pasukistudio.elyrabudget"
    private static let key = "elyraBudget.widget.snapshot"

    static func write(
        groups: [BudgetGroup],
        currencyCode: String,
        month: Date = .now
    ) {
        guard let group = groups.first(where: { !$0.isArchived }) else { return }
        let transactions = group.transactions ?? []
        let spent = transactions
            .filter { $0.date.isInSameMonth(as: month) }
            .reduce(Decimal.zero) { $0 + $1.budgetImpact }
        let goals = group.savingsGoals ?? []
        let progress = goals.isEmpty
            ? 0
            : goals.reduce(0.0) { $0 + $1.visualProgress } / Double(goals.count)
        let snapshot = ElyraWidgetSnapshot(
            groupName: group.name,
            spent: spent,
            budget: group.monthlyBudget(for: month),
            savingsProgress: progress,
            currencyCode: currencyCode,
            updatedAt: .now
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            UserDefaults(suiteName: appGroup)?.set(data, forKey: key)
        } catch {
            AppLogger.persistence.error("Widget-Daten konnten nicht gespeichert werden: \(error)")
            return
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func clear() {
        UserDefaults(suiteName: appGroup)?.removeObject(forKey: key)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
