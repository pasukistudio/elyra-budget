import Foundation
import SwiftData

/// A portable, local backup of the user's own Elyra Budget data.
/// CloudKit sharing metadata is intentionally not included; the records are
/// imported into the currently configured container and can then be shared again.
struct ElyraBudgetBackup: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let exportedAt: Date
    let profiles: [ProfileBackup]
    let groups: [GroupBackup]
    let allocations: [AllocationBackup]
    let budgets: [BudgetBackup]
    let fixedCosts: [FixedCostBackup]
    let savingsGoals: [SavingsGoalBackup]
    let contributions: [ContributionBackup]
    let transactions: [TransactionBackup]
}

struct ProfileBackup: Codable {
    let name: String
    let appearanceRawValue: String
    let accentColorRawValue: String
    let customAccentHex: String
    let currencyRawValue: String
    let greenBudgetThreshold: Int
    let orangeBudgetThreshold: Int
    let budgetNotificationsEnabled: Bool
    let savingsContributionNotificationsEnabled: Bool
    let syncErrorNotificationsEnabled: Bool
    let savingsGoalCompletionNotificationsEnabled: Bool
    let automaticBookingFailureNotificationsEnabled: Bool
    let monthlySummaryNotificationsEnabled: Bool
    let forecastRiskNotificationsEnabled: Bool
    let overdueFixedCostNotificationsEnabled: Bool
    let syncRecoveryNotificationsEnabled: Bool
    let feedbackStatusNotificationsEnabled: Bool
    let unusualExpenseNotificationsEnabled: Bool
    let dailyDigestNotificationsEnabled: Bool
    let appLockEnabled: Bool
    let notificationQuietHoursEnabled: Bool
    let notificationQuietHoursStart: Int
    let notificationQuietHoursEnd: Int
    let createdAt: Date
    let updatedAt: Date
}

struct GroupBackup: Codable {
    let id: UUID
    let name: String
    let iconName: String
    let iconColorHex: String
    let sortOrder: Int
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date
    let standardMonthlyBudget: Decimal
    let roundUpTransactionsEnabled: Bool
    let roundUpReserveID: UUID?
}

struct AllocationBackup: Codable {
    let groupID: UUID
    let monthStart: Date
    let amount: Decimal
    let createdAt: Date
    let updatedAt: Date
}

struct BudgetBackup: Codable {
    let id: UUID
    let name: String
    let iconName: String
    let iconColorHex: String
    let limit: Decimal
    let includesFixedCosts: Bool
    let groupID: UUID?
    let sortOrder: Int
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date
}

struct FixedCostBackup: Codable {
    let id: UUID
    let title: String
    let amount: Decimal
    let frequencyRawValue: String
    let scheduleRawValue: String
    let anchorDate: Date
    let configurationEffectiveDate: Date?
    let dayOfMonth: Int
    let automaticBooking: Bool
    let reminderEnabled: Bool
    let isPaused: Bool
    let pauseUntil: Date?
    let note: String
    let budgetID: UUID?
    let groupID: UUID?
    let createdAt: Date
    let updatedAt: Date
}

struct SavingsGoalBackup: Codable {
    let id: UUID
    let name: String
    let typeRawValue: String
    let targetAmount: Decimal?
    let targetDate: Date?
    let contributionAmount: Decimal
    let frequencyRawValue: String
    let scheduleRawValue: String
    let anchorDate: Date
    let dayOfMonth: Int
    let automaticBooking: Bool
    let note: String
    let iconName: String
    let iconColorHex: String
    let sortOrder: Int
    let isArchived: Bool
    let groupID: UUID?
    let budgetID: UUID?
    let fixedCostID: UUID?
    let createdAt: Date
    let updatedAt: Date
}

struct ContributionBackup: Codable {
    let id: UUID
    let amount: Decimal
    let date: Date
    let note: String
    let automatic: Bool
    let occurrenceDate: Date?
    let goalID: UUID?
    let transactionID: UUID?
}

struct TransactionBackup: Codable {
    let id: UUID
    let title: String
    let amount: Decimal
    let date: Date
    let note: String
    let receiptFilename: String?
    let receiptData: Data?
    let typeRawValue: String
    let budgetID: UUID?
    let groupID: UUID?
    let fixedCostID: UUID?
    let fixedCostOccurrenceDate: Date?
    let fixedCostBookingAutomatic: Bool?
    let savingsGoalCoveredAmount: Decimal?
    let savingsGoalID: UUID?
    let savingsContributionID: UUID?
    let savingsGoalOccurrenceDate: Date?
    let roundUpOriginalAmount: Decimal?
    let roundUpSavingsContributionID: UUID?
    let createdAt: Date
    let updatedAt: Date
}

enum ElyraBudgetBackupError: LocalizedError {
    case invalidFile
    case unsupportedVersion(Int)
    case saveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "Die Sicherungsdatei ist ungültig oder unvollständig."
        case .unsupportedVersion(let version):
            return "Diese Sicherungsdatei benötigt eine neuere App-Version (Version \(version))."
        case .saveFailed(let error):
            return "Die importierten Daten konnten nicht gespeichert werden: \(error.localizedDescription)"
        }
    }
}

@MainActor
enum ElyraBudgetBackupService {
    static func exportData(from modelContext: ModelContext) throws -> Data {
        let backup = ElyraBudgetBackup(
            schemaVersion: ElyraBudgetBackup.currentSchemaVersion,
            exportedAt: .now,
            profiles: try modelContext.fetch(FetchDescriptor<UserSettings>()).map(ProfileBackup.init),
            groups: try modelContext.fetch(FetchDescriptor<BudgetGroup>()).map(GroupBackup.init),
            allocations: try modelContext.fetch(FetchDescriptor<BudgetGroupMonthlyAllocation>()).compactMap(AllocationBackup.init),
            budgets: try modelContext.fetch(FetchDescriptor<Budget>()).map(BudgetBackup.init),
            fixedCosts: try modelContext.fetch(FetchDescriptor<FixedCost>()).map(FixedCostBackup.init),
            savingsGoals: try modelContext.fetch(FetchDescriptor<SavingsGoal>()).map(SavingsGoalBackup.init),
            contributions: try modelContext.fetch(FetchDescriptor<SavingsContribution>()).map(ContributionBackup.init),
            transactions: try modelContext.fetch(FetchDescriptor<Transaction>()).map(TransactionBackup.init)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    /// Replaces the current local store. This is intentional: it preserves IDs
    /// and relationships and is the reliable mode for moving to a new container.
    static func importData(_ data: Data, into modelContext: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: ElyraBudgetBackup
        do {
            backup = try decoder.decode(ElyraBudgetBackup.self, from: data)
        } catch {
            throw ElyraBudgetBackupError.invalidFile
        }

        guard backup.schemaVersion <= ElyraBudgetBackup.currentSchemaVersion else {
            throw ElyraBudgetBackupError.unsupportedVersion(backup.schemaVersion)
        }

        deleteCurrentData(from: modelContext)

        let groups = Dictionary(uniqueKeysWithValues: backup.groups.map { item in
            let group = BudgetGroup(name: item.name)
            group.id = item.id
            group.iconName = item.iconName
            group.iconColorHex = item.iconColorHex
            group.sortOrder = item.sortOrder
            group.isArchived = item.isArchived
            group.createdAt = item.createdAt
            group.updatedAt = item.updatedAt
            group.standardMonthlyBudget = item.standardMonthlyBudget
            group.roundUpTransactionsEnabled = item.roundUpTransactionsEnabled
            group.roundUpReserveID = item.roundUpReserveID
            modelContext.insert(group)
            return (item.id, group)
        })

        for item in backup.allocations {
            guard let group = groups[item.groupID] else { continue }
            let allocation = BudgetGroupMonthlyAllocation(
                monthStart: item.monthStart,
                amount: item.amount,
                group: group
            )
            allocation.createdAt = item.createdAt
            allocation.updatedAt = item.updatedAt
            modelContext.insert(allocation)
        }

        let budgets = Dictionary(uniqueKeysWithValues: backup.budgets.map { item in
            let budget = Budget(name: item.name, group: item.groupID.flatMap { groups[$0] })
            budget.id = item.id
            budget.iconName = item.iconName
            budget.iconColorHex = item.iconColorHex
            budget.limit = item.limit
            budget.includesFixedCosts = item.includesFixedCosts
            budget.sortOrder = item.sortOrder
            budget.isArchived = item.isArchived
            budget.createdAt = item.createdAt
            budget.updatedAt = item.updatedAt
            modelContext.insert(budget)
            return (item.id, budget)
        })

        let fixedCosts = Dictionary(uniqueKeysWithValues: backup.fixedCosts.map { item in
            let fixedCost = FixedCost(
                title: item.title,
                amount: item.amount,
                frequency: FixedCostFrequency(rawValue: item.frequencyRawValue) ?? .monthly,
                schedule: FixedCostSchedule(rawValue: item.scheduleRawValue) ?? .fixedDay,
                anchorDate: item.anchorDate,
                dayOfMonth: item.dayOfMonth,
                automaticBooking: item.automaticBooking,
                reminderEnabled: item.reminderEnabled,
                budget: item.budgetID.flatMap { budgets[$0] },
                group: item.groupID.flatMap { groups[$0] }
            )
            fixedCost.id = item.id
            fixedCost.configurationEffectiveDate = item.configurationEffectiveDate
            fixedCost.isPaused = item.isPaused
            fixedCost.pauseUntil = item.pauseUntil
            fixedCost.note = item.note
            fixedCost.createdAt = item.createdAt
            fixedCost.updatedAt = item.updatedAt
            modelContext.insert(fixedCost)
            return (item.id, fixedCost)
        })

        let savingsGoals = Dictionary(uniqueKeysWithValues: backup.savingsGoals.map { item in
            let goal = SavingsGoal(
                name: item.name,
                type: SavingsGoalType(rawValue: item.typeRawValue) ?? .goal,
                targetAmount: item.targetAmount,
                targetDate: item.targetDate,
                contributionAmount: item.contributionAmount,
                frequency: SavingsFrequency(rawValue: item.frequencyRawValue) ?? .monthly,
                schedule: SavingsSchedule(rawValue: item.scheduleRawValue) ?? .fixedDay,
                anchorDate: item.anchorDate,
                automaticBooking: item.automaticBooking,
                budget: item.budgetID.flatMap { budgets[$0] },
                fixedCost: item.fixedCostID.flatMap { fixedCosts[$0] },
                group: item.groupID.flatMap { groups[$0] }
            )
            goal.id = item.id
            goal.dayOfMonth = item.dayOfMonth
            goal.note = item.note
            goal.iconName = item.iconName
            goal.iconColorHex = item.iconColorHex
            goal.sortOrder = item.sortOrder
            goal.isArchived = item.isArchived
            goal.createdAt = item.createdAt
            goal.updatedAt = item.updatedAt
            modelContext.insert(goal)
            return (item.id, goal)
        })

        for item in backup.contributions {
            let contribution = SavingsContribution(
                amount: item.amount,
                date: item.date,
                note: item.note,
                automatic: item.automatic,
                occurrenceDate: item.occurrenceDate,
                goal: item.goalID.flatMap { savingsGoals[$0] }
            )
            contribution.id = item.id
            contribution.transactionID = item.transactionID
            modelContext.insert(contribution)
        }

        for item in backup.transactions {
            let transaction = Transaction(
                title: item.title,
                amount: item.amount,
                date: item.date,
                note: item.note,
                type: TransactionType(rawValue: item.typeRawValue) ?? .expense,
                budget: item.budgetID.flatMap { budgets[$0] },
                group: item.groupID.flatMap { groups[$0] }
            )
            transaction.id = item.id
            transaction.receiptFilename = item.receiptFilename
            transaction.receiptData = item.receiptData
            transaction.fixedCostID = item.fixedCostID
            transaction.fixedCostOccurrenceDate = item.fixedCostOccurrenceDate
            transaction.fixedCostBookingAutomatic = item.fixedCostBookingAutomatic
            transaction.savingsGoalCoveredAmount = item.savingsGoalCoveredAmount
            transaction.savingsGoalID = item.savingsGoalID
            transaction.savingsContributionID = item.savingsContributionID
            transaction.savingsGoalOccurrenceDate = item.savingsGoalOccurrenceDate
            transaction.roundUpOriginalAmount = item.roundUpOriginalAmount
            transaction.roundUpSavingsContributionID = item.roundUpSavingsContributionID
            transaction.createdAt = item.createdAt
            transaction.updatedAt = item.updatedAt
            modelContext.insert(transaction)
        }

        for item in backup.profiles {
            let profile = UserSettings(
                name: item.name,
                appearanceRawValue: item.appearanceRawValue,
                accentColorRawValue: item.accentColorRawValue,
                customAccentHex: item.customAccentHex,
                currencyRawValue: item.currencyRawValue,
                greenBudgetThreshold: item.greenBudgetThreshold,
                orangeBudgetThreshold: item.orangeBudgetThreshold,
                budgetNotificationsEnabled: item.budgetNotificationsEnabled,
                savingsContributionNotificationsEnabled: item.savingsContributionNotificationsEnabled,
                syncErrorNotificationsEnabled: item.syncErrorNotificationsEnabled,
                savingsGoalCompletionNotificationsEnabled: item.savingsGoalCompletionNotificationsEnabled,
                automaticBookingFailureNotificationsEnabled: item.automaticBookingFailureNotificationsEnabled,
                monthlySummaryNotificationsEnabled: item.monthlySummaryNotificationsEnabled,
                forecastRiskNotificationsEnabled: item.forecastRiskNotificationsEnabled,
                overdueFixedCostNotificationsEnabled: item.overdueFixedCostNotificationsEnabled,
                syncRecoveryNotificationsEnabled: item.syncRecoveryNotificationsEnabled,
                feedbackStatusNotificationsEnabled: item.feedbackStatusNotificationsEnabled,
                unusualExpenseNotificationsEnabled: item.unusualExpenseNotificationsEnabled,
                dailyDigestNotificationsEnabled: item.dailyDigestNotificationsEnabled,
                appLockEnabled: item.appLockEnabled,
                notificationQuietHoursEnabled: item.notificationQuietHoursEnabled,
                notificationQuietHoursStart: item.notificationQuietHoursStart,
                notificationQuietHoursEnd: item.notificationQuietHoursEnd
            )
            profile.createdAt = item.createdAt
            profile.updatedAt = item.updatedAt
            modelContext.insert(profile)
        }

        do {
            try modelContext.save()
        } catch {
            throw ElyraBudgetBackupError.saveFailed(error)
        }
    }

    private static func deleteCurrentData(from modelContext: ModelContext) {
        delete(SavingsContribution.self, from: modelContext)
        delete(Transaction.self, from: modelContext)
        delete(SavingsGoal.self, from: modelContext)
        delete(FixedCost.self, from: modelContext)
        delete(Budget.self, from: modelContext)
        delete(BudgetGroupMonthlyAllocation.self, from: modelContext)
        delete(BudgetGroup.self, from: modelContext)
        delete(UserSettings.self, from: modelContext)
    }

    private static func delete<Model: PersistentModel>(
        _ type: Model.Type,
        from modelContext: ModelContext
    ) {
        if let items = try? modelContext.fetch(FetchDescriptor<Model>()) {
            items.forEach(modelContext.delete)
        }
    }
}

private extension ProfileBackup {
    init(_ profile: UserSettings) {
        name = profile.name
        appearanceRawValue = profile.appearanceRawValue
        accentColorRawValue = profile.accentColorRawValue
        customAccentHex = profile.customAccentHex
        currencyRawValue = profile.currencyRawValue
        greenBudgetThreshold = profile.greenBudgetThreshold
        orangeBudgetThreshold = profile.orangeBudgetThreshold
        budgetNotificationsEnabled = profile.budgetNotificationsEnabled
        savingsContributionNotificationsEnabled = profile.savingsContributionNotificationsEnabled
        syncErrorNotificationsEnabled = profile.syncErrorNotificationsEnabled
        savingsGoalCompletionNotificationsEnabled = profile.savingsGoalCompletionNotificationsEnabled
        automaticBookingFailureNotificationsEnabled = profile.automaticBookingFailureNotificationsEnabled
        monthlySummaryNotificationsEnabled = profile.monthlySummaryNotificationsEnabled
        forecastRiskNotificationsEnabled = profile.forecastRiskNotificationsEnabled
        overdueFixedCostNotificationsEnabled = profile.overdueFixedCostNotificationsEnabled
        syncRecoveryNotificationsEnabled = profile.syncRecoveryNotificationsEnabled
        feedbackStatusNotificationsEnabled = profile.feedbackStatusNotificationsEnabled
        unusualExpenseNotificationsEnabled = profile.unusualExpenseNotificationsEnabled
        dailyDigestNotificationsEnabled = profile.dailyDigestNotificationsEnabled
        appLockEnabled = profile.appLockEnabled
        notificationQuietHoursEnabled = profile.notificationQuietHoursEnabled
        notificationQuietHoursStart = profile.notificationQuietHoursStart
        notificationQuietHoursEnd = profile.notificationQuietHoursEnd
        createdAt = profile.createdAt
        updatedAt = profile.updatedAt
    }
}

private extension GroupBackup {
    init(_ group: BudgetGroup) {
        id = group.id
        name = group.name
        iconName = group.iconName
        iconColorHex = group.iconColorHex
        sortOrder = group.sortOrder
        isArchived = group.isArchived
        createdAt = group.createdAt
        updatedAt = group.updatedAt
        standardMonthlyBudget = group.standardMonthlyBudget
        roundUpTransactionsEnabled = group.roundUpTransactionsEnabled
        roundUpReserveID = group.roundUpReserveID
    }
}

private extension AllocationBackup {
    init?(_ allocation: BudgetGroupMonthlyAllocation) {
        guard let groupID = allocation.group?.id else { return nil }
        self.init(
            groupID: groupID,
            monthStart: allocation.monthStart,
            amount: allocation.amount,
            createdAt: allocation.createdAt,
            updatedAt: allocation.updatedAt
        )
    }
}

private extension BudgetBackup {
    init(_ budget: Budget) {
        id = budget.id
        name = budget.name
        iconName = budget.iconName
        iconColorHex = budget.iconColorHex
        limit = budget.limit
        includesFixedCosts = budget.includesFixedCosts
        groupID = budget.group?.id
        sortOrder = budget.sortOrder
        isArchived = budget.isArchived
        createdAt = budget.createdAt
        updatedAt = budget.updatedAt
    }
}

private extension FixedCostBackup {
    init(_ fixedCost: FixedCost) {
        id = fixedCost.id
        title = fixedCost.title
        amount = fixedCost.amount
        frequencyRawValue = fixedCost.frequencyRawValue
        scheduleRawValue = fixedCost.scheduleRawValue
        anchorDate = fixedCost.anchorDate
        configurationEffectiveDate = fixedCost.configurationEffectiveDate
        dayOfMonth = fixedCost.dayOfMonth
        automaticBooking = fixedCost.automaticBooking
        reminderEnabled = fixedCost.reminderEnabled
        isPaused = fixedCost.isPaused
        pauseUntil = fixedCost.pauseUntil
        note = fixedCost.note
        budgetID = fixedCost.budget?.id
        groupID = fixedCost.group?.id
        createdAt = fixedCost.createdAt
        updatedAt = fixedCost.updatedAt
    }
}

private extension SavingsGoalBackup {
    init(_ goal: SavingsGoal) {
        id = goal.id
        name = goal.name
        typeRawValue = goal.typeRawValue
        targetAmount = goal.targetAmount
        targetDate = goal.targetDate
        contributionAmount = goal.contributionAmount
        frequencyRawValue = goal.frequencyRawValue
        scheduleRawValue = goal.scheduleRawValue
        anchorDate = goal.anchorDate
        dayOfMonth = goal.dayOfMonth
        automaticBooking = goal.automaticBooking
        note = goal.note
        iconName = goal.iconName
        iconColorHex = goal.iconColorHex
        sortOrder = goal.sortOrder
        isArchived = goal.isArchived
        groupID = goal.group?.id
        budgetID = goal.budget?.id
        fixedCostID = goal.fixedCost?.id
        createdAt = goal.createdAt
        updatedAt = goal.updatedAt
    }
}

private extension ContributionBackup {
    init(_ contribution: SavingsContribution) {
        id = contribution.id
        amount = contribution.amount
        date = contribution.date
        note = contribution.note
        automatic = contribution.automatic
        occurrenceDate = contribution.occurrenceDate
        goalID = contribution.goal?.id
        transactionID = contribution.transactionID
    }
}

private extension TransactionBackup {
    init(_ transaction: Transaction) {
        id = transaction.id
        title = transaction.title
        amount = transaction.amount
        date = transaction.date
        note = transaction.note
        receiptFilename = transaction.receiptFilename
        receiptData = transaction.receiptData ?? transaction.receiptFilename.flatMap(TransactionReceiptService.data(for:))
        typeRawValue = transaction.typeRawValue
        budgetID = transaction.budget?.id
        groupID = transaction.group?.id
        fixedCostID = transaction.fixedCostID
        fixedCostOccurrenceDate = transaction.fixedCostOccurrenceDate
        fixedCostBookingAutomatic = transaction.fixedCostBookingAutomatic
        savingsGoalCoveredAmount = transaction.savingsGoalCoveredAmount
        savingsGoalID = transaction.savingsGoalID
        savingsContributionID = transaction.savingsContributionID
        savingsGoalOccurrenceDate = transaction.savingsGoalOccurrenceDate
        roundUpOriginalAmount = transaction.roundUpOriginalAmount
        roundUpSavingsContributionID = transaction.roundUpSavingsContributionID
        createdAt = transaction.createdAt
        updatedAt = transaction.updatedAt
    }
}
