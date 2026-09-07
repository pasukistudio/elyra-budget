import Foundation
import SwiftData

enum TransactionRoundUpService {
    static let reserveName = "Aufrundungs-Rücklage"

    static func enable(
        for group: BudgetGroup,
        transactions: [Transaction],
        savingsGoals: [SavingsGoal],
        contributions: [SavingsContribution],
        modelContext: ModelContext
    ) throws {
        let reserve = reserve(
            for: group,
            in: savingsGoals,
            modelContext: modelContext
        )
        group.roundUpTransactionsEnabled = true
        group.roundUpReserveID = reserve.id
        group.updatedAt = .now

        var deletedContributionIDs: [UUID] = []
        for transaction in transactions where transaction.effectiveGroup === group {
            if let deletedContributionID = try apply(
                to: transaction,
                group: group,
                reserve: reserve,
                contributions: contributions,
                modelContext: modelContext
            ) {
                deletedContributionIDs.append(deletedContributionID)
            }
        }

        guard modelContext.hasChanges else { return }
        try modelContext.save()
        recordDeletions(deletedContributionIDs, groupID: group.id)
    }

    static func applyIfNeeded(
        to transaction: Transaction,
        group: BudgetGroup?,
        savingsGoals: [SavingsGoal],
        contributions: [SavingsContribution],
        modelContext: ModelContext
    ) throws {
        guard let group,
              group.roundUpTransactionsEnabled,
              transaction.effectiveGroup === group else {
            return
        }
        let reserve = reserve(
            for: group,
            in: savingsGoals,
            modelContext: modelContext
        )
        let deletedContributionID = try apply(
            to: transaction,
            group: group,
            reserve: reserve,
            contributions: contributions,
            modelContext: modelContext
        )
        guard modelContext.hasChanges else { return }
        try modelContext.save()
        if let deletedContributionID {
            recordDeletions([deletedContributionID], groupID: group.id)
        }
    }

    static func applyAllIfNeeded(
        transactions: [Transaction],
        groups: [BudgetGroup],
        savingsGoals: [SavingsGoal],
        contributions: [SavingsContribution],
        modelContext: ModelContext
    ) throws {
        for transaction in transactions {
            let group = transaction.effectiveGroup
            guard let group, groups.contains(where: { $0 === group }) else { continue }
            try applyIfNeeded(
                to: transaction,
                group: group,
                savingsGoals: savingsGoals,
                contributions: contributions,
                modelContext: modelContext
            )
        }
        guard modelContext.hasChanges else { return }
        try modelContext.save()
    }

    private static func recordDeletions(_ ids: [UUID], groupID: UUID) {
        for id in ids {
            CloudKitSharedAreaService.recordDeletion(
                key: id.uuidString,
                kind: .contribution,
                groupID: groupID
            )
        }
    }

    private static func apply(
        to transaction: Transaction,
        group: BudgetGroup,
        reserve: SavingsGoal,
        contributions: [SavingsContribution],
        modelContext: ModelContext
    ) throws -> UUID? {
        // Round spending only. Income and refunds must retain their exact amount.
        guard transaction.type == .expense,
              transaction.savingsGoalID == nil else {
            return removeExistingContribution(
                from: transaction,
                contributions: contributions,
                modelContext: modelContext
            )
        }

        var originalAmount = transaction.roundUpOriginalAmount ?? transaction.amount
        guard originalAmount > 0 else { return nil }

        var roundedAmount = Decimal.zero
        NSDecimalRound(&roundedAmount, &originalAmount, 0, .up)
        let difference = roundedAmount - originalAmount

        transaction.amount = roundedAmount
        transaction.roundUpOriginalAmount = difference > 0 ? originalAmount : nil
        transaction.updatedAt = .now

        guard difference > 0 else {
            return removeExistingContribution(
                from: transaction,
                contributions: contributions,
                modelContext: modelContext
            )
        }

        if let contributionID = transaction.roundUpSavingsContributionID,
           let existing = contributions.first(where: { $0.id == contributionID }) {
            existing.amount = difference
            existing.date = transaction.date
            existing.updatedAt = .now
            existing.note = "Aufrundung für \(transaction.title)"
            existing.goal = reserve
        } else {
            let contribution = SavingsContribution(
                amount: difference,
                date: transaction.date,
                note: "Aufrundung für \(transaction.title)",
                automatic: true,
                occurrenceDate: transaction.date,
                goal: reserve
            )
            contribution.transactionID = transaction.id
            transaction.roundUpSavingsContributionID = contribution.id
            modelContext.insert(contribution)
        }

        _ = group
        return nil
    }

    private static func removeExistingContribution(
        from transaction: Transaction,
        contributions: [SavingsContribution],
        modelContext: ModelContext
    ) -> UUID? {
        guard let contributionID = transaction.roundUpSavingsContributionID,
              let contribution = contributions.first(where: { $0.id == contributionID }) else {
            transaction.roundUpSavingsContributionID = nil
            return nil
        }
        modelContext.delete(contribution)
        transaction.roundUpSavingsContributionID = nil
        return contribution.id
    }

    private static func reserve(
        for group: BudgetGroup,
        in savingsGoals: [SavingsGoal],
        modelContext: ModelContext
    ) -> SavingsGoal {
        if let reserveID = group.roundUpReserveID,
           let existing = savingsGoals.first(where: { $0.id == reserveID }) {
            return existing
        }

        if let existing = savingsGoals.first(where: {
            !$0.isArchived && $0.type == .reserve && $0.group === group && $0.name == reserveName
        }) {
            group.roundUpReserveID = existing.id
            return existing
        }

        let created = SavingsGoal(
            name: reserveName,
            type: .reserve,
            group: group
        )
        created.note = "Automatisch gesammelte Rundungsdifferenzen"
        modelContext.insert(created)
        group.roundUpReserveID = created.id
        return created
    }
}
