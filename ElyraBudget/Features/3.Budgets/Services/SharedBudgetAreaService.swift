import Foundation
import CloudKit
import SwiftData

@MainActor
final class CloudKitSharedAreaService {
    static let shared = CloudKitSharedAreaService()

    static let containerIdentifier = "iCloud.de.pasukistudio.elyrabudget"
    private let container = CKContainer(identifier: containerIdentifier)
    private let zoneID = CKRecordZone.ID(zoneName: "SharedBudgetAreas", ownerName: CKCurrentUserDefaultName)
    private let sharedAreaPrefix = "elyraBudget.cloudKitSharedArea."

    private init() {}

    func prepareShare(for group: BudgetGroup) async throws -> CKShare {
        let database = container.privateCloudDatabase
        let zone = CKRecordZone(zoneID: zoneID)
        do {
            _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
        } catch {
            // A second save of the same custom zone is harmless; record access
            // below still verifies that the zone is available.
        }

        let recordID = CKRecord.ID(recordName: group.id.uuidString, zoneID: zoneID)
        let root: CKRecord
        do {
            root = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            root = CKRecord(recordType: "SharedBudgetArea", recordID: recordID)
        }

        root["groupID"] = group.id.uuidString as CKRecordValue
        root["name"] = group.name as CKRecordValue
        root["payload"] = try SharedBudgetAreaSnapshot(group: group).encodedData() as CKRecordValue
        root["updatedAt"] = Date() as CKRecordValue

        let share: CKShare
        if let shareReference = root.share {
            guard let existingShare = try await database.record(for: shareReference.recordID) as? CKShare else {
                throw SharedBudgetAreaError.invalidShareRecord
            }
            share = existingShare
        } else {
            share = CKShare(rootRecord: root)
            share[CKShare.SystemFieldKey.title] = group.name as CKRecordValue
            share.publicPermission = .none
        }

        _ = try await database.modifyRecords(saving: [root, share], deleting: [])
        UserDefaults.standard.set(true, forKey: sharedAreaKey(for: group.id))
        return share
    }

    func importAcceptedShare(
        metadata: CKShare.Metadata,
        modelContext: ModelContext
    ) async throws -> BudgetGroup {
        guard let rootRecordID = metadata.hierarchicalRootRecordID else {
            throw SharedBudgetAreaError.invalidShareRecord
        }
        let record = try await container.sharedCloudDatabase.record(for: rootRecordID)
        guard let data = record["payload"] as? Data else {
            throw SharedBudgetAreaError.unsupportedPayload
        }
        let group = try SharedBudgetAreaSnapshot.decode(data).apply(to: modelContext)
        UserDefaults.standard.set(true, forKey: sharedAreaKey(for: group.id))
        return group
    }

    func importPendingShare(modelContext: ModelContext) async throws -> BudgetGroup? {
        let defaults = UserDefaults.standard
        guard let recordName = defaults.string(forKey: "elyraBudget.pendingCloudKitShare.recordName"),
              let zoneName = defaults.string(forKey: "elyraBudget.pendingCloudKitShare.zoneName"),
              let ownerName = defaults.string(forKey: "elyraBudget.pendingCloudKitShare.ownerName") else {
            return nil
        }

        let recordID = CKRecord.ID(
            recordName: recordName,
            zoneID: CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
        )
        let record = try await container.sharedCloudDatabase.record(for: recordID)
        guard let data = record["payload"] as? Data else {
            throw SharedBudgetAreaError.unsupportedPayload
        }
        let group = try SharedBudgetAreaSnapshot.decode(data).apply(to: modelContext)
        defaults.set(true, forKey: sharedAreaKey(for: group.id))
        defaults.removeObject(forKey: "elyraBudget.pendingCloudKitShare.recordName")
        defaults.removeObject(forKey: "elyraBudget.pendingCloudKitShare.zoneName")
        defaults.removeObject(forKey: "elyraBudget.pendingCloudKitShare.ownerName")
        return group
    }

    func updateSharedArea(
        group: BudgetGroup
    ) async throws {
        guard UserDefaults.standard.bool(forKey: sharedAreaKey(for: group.id)) else { return }
        let database = container.privateCloudDatabase
        let recordID = CKRecord.ID(recordName: group.id.uuidString, zoneID: zoneID)
        let record = try await database.record(for: recordID)
        record["name"] = group.name as CKRecordValue
        record["payload"] = try SharedBudgetAreaSnapshot(group: group).encodedData() as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        _ = try await database.modifyRecords(saving: [record], deleting: [])
    }

    func pullSharedArea(
        group: BudgetGroup,
        modelContext: ModelContext
    ) async throws {
        guard UserDefaults.standard.bool(forKey: sharedAreaKey(for: group.id)) else { return }
        let recordID = CKRecord.ID(recordName: group.id.uuidString, zoneID: zoneID)
        let record: CKRecord
        do {
            record = try await container.privateCloudDatabase.record(for: recordID)
        } catch {
            record = try await container.sharedCloudDatabase.record(for: recordID)
        }
        guard let data = record["payload"] as? Data else {
            throw SharedBudgetAreaError.unsupportedPayload
        }
        _ = try SharedBudgetAreaSnapshot.decode(data).apply(to: modelContext)
    }

    private func sharedAreaKey(for groupID: UUID) -> String {
        sharedAreaPrefix + groupID.uuidString
    }
}

enum SharedBudgetAreaError: LocalizedError {
    case unsupportedPayload
    case invalidShareRecord

    var errorDescription: String? {
        switch self {
        case .unsupportedPayload:
            return "Die geteilten Bereichsdaten konnten nicht gelesen werden."
        case .invalidShareRecord:
            return "Der geteilte Budgetbereich ist nicht gültig und konnte nicht geöffnet werden."
        }
    }
}

struct SharedBudgetAreaSnapshot: Codable {
    struct Group: Codable {
        let id: UUID
        let name: String
        let iconName: String
        let iconColorHex: String
        let sortOrder: Int
        let isArchived: Bool
        let createdAt: Date
        let updatedAt: Date
        let standardMonthlyBudget: Decimal
    }

    struct Allocation: Codable {
        let monthStart: Date
        let amount: Decimal
        let createdAt: Date
        let updatedAt: Date
    }

    struct Budget: Codable {
        let id: UUID
        let name: String
        let iconName: String
        let iconColorHex: String
        let limit: Decimal
        let includesFixedCosts: Bool
        let sortOrder: Int
        let isArchived: Bool
        let createdAt: Date
        let updatedAt: Date
    }

    struct Transaction: Codable {
        let id: UUID
        let title: String
        let amount: Decimal
        let date: Date
        let note: String
        let typeRawValue: String
        let fixedCostID: UUID?
        let fixedCostOccurrenceDate: Date?
        let fixedCostBookingAutomatic: Bool?
        let savingsGoalCoveredAmount: Decimal?
        let savingsGoalID: UUID?
        let savingsGoalOccurrenceDate: Date?
        let savingsContributionID: UUID?
        let budgetID: UUID?
    }

    struct FixedCost: Codable {
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
        let createdAt: Date
        let updatedAt: Date
        let budgetID: UUID?
    }

    struct SavingsGoal: Codable {
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
        let createdAt: Date
        let updatedAt: Date
        let budgetID: UUID?
        let fixedCostID: UUID?
    }

    struct Contribution: Codable {
        let id: UUID
        let amount: Decimal
        let date: Date
        let note: String
        let automatic: Bool
        let occurrenceDate: Date?
        let transactionID: UUID?
        let goalID: UUID
    }

    let group: Group
    let allocations: [Allocation]
    let budgets: [Budget]
    let transactions: [Transaction]
    let fixedCosts: [FixedCost]
    let savingsGoals: [SavingsGoal]
    let contributions: [Contribution]

    init(group: BudgetGroup) {
        self.group = Group(
            id: group.id,
            name: group.name,
            iconName: group.iconName,
            iconColorHex: group.iconColorHex,
            sortOrder: group.sortOrder,
            isArchived: group.isArchived,
            createdAt: group.createdAt,
            updatedAt: group.updatedAt,
            standardMonthlyBudget: group.standardMonthlyBudget
        )
        self.allocations = (group.monthlyAllocations ?? []).map {
            Allocation(
                monthStart: $0.monthStart,
                amount: $0.amount,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        let groupBudgets = group.budgets ?? []
        self.budgets = groupBudgets.map {
            Budget(
                id: $0.id,
                name: $0.name,
                iconName: $0.iconName,
                iconColorHex: $0.iconColorHex,
                limit: $0.limit,
                includesFixedCosts: $0.includesFixedCosts,
                sortOrder: $0.sortOrder,
                isArchived: $0.isArchived,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            )
        }
        self.transactions = (group.transactions ?? []).map {
            Transaction(
                id: $0.id,
                title: $0.title,
                amount: $0.amount,
                date: $0.date,
                note: $0.note,
                typeRawValue: $0.typeRawValue,
                fixedCostID: $0.fixedCostID,
                fixedCostOccurrenceDate: $0.fixedCostOccurrenceDate,
                fixedCostBookingAutomatic: $0.fixedCostBookingAutomatic,
                savingsGoalCoveredAmount: $0.savingsGoalCoveredAmount,
                savingsGoalID: $0.savingsGoalID,
                savingsGoalOccurrenceDate: $0.savingsGoalOccurrenceDate,
                savingsContributionID: $0.savingsContributionID,
                budgetID: $0.budget?.id
            )
        }
        self.fixedCosts = (group.fixedCosts ?? []).map {
            FixedCost(
                id: $0.id,
                title: $0.title,
                amount: $0.amount,
                frequencyRawValue: $0.frequencyRawValue,
                scheduleRawValue: $0.scheduleRawValue,
                anchorDate: $0.anchorDate,
                configurationEffectiveDate: $0.configurationEffectiveDate,
                dayOfMonth: $0.dayOfMonth,
                automaticBooking: $0.automaticBooking,
                reminderEnabled: $0.reminderEnabled,
                isPaused: $0.isPaused,
                pauseUntil: $0.pauseUntil,
                note: $0.note,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                budgetID: $0.budget?.id
            )
        }
        self.savingsGoals = (group.savingsGoals ?? []).map {
            SavingsGoal(
                id: $0.id,
                name: $0.name,
                typeRawValue: $0.typeRawValue,
                targetAmount: $0.targetAmount,
                targetDate: $0.targetDate,
                contributionAmount: $0.contributionAmount,
                frequencyRawValue: $0.frequencyRawValue,
                scheduleRawValue: $0.scheduleRawValue,
                anchorDate: $0.anchorDate,
                dayOfMonth: $0.dayOfMonth,
                automaticBooking: $0.automaticBooking,
                note: $0.note,
                iconName: $0.iconName,
                iconColorHex: $0.iconColorHex,
                sortOrder: $0.sortOrder,
                isArchived: $0.isArchived,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                budgetID: $0.budget?.id,
                fixedCostID: $0.fixedCost?.id
            )
        }
        self.contributions = (group.savingsGoals ?? []).flatMap { goal in
            (goal.contributions ?? []).map {
                Contribution(
                    id: $0.id,
                    amount: $0.amount,
                    date: $0.date,
                    note: $0.note,
                    automatic: $0.automatic,
                    occurrenceDate: $0.occurrenceDate,
                    transactionID: $0.transactionID,
                    goalID: goal.id
                )
            }
        }
    }

    private init(
        group: Group,
        allocations: [Allocation],
        budgets: [Budget],
        transactions: [Transaction],
        fixedCosts: [FixedCost],
        savingsGoals: [SavingsGoal],
        contributions: [Contribution]
    ) {
        self.group = group
        self.allocations = allocations
        self.budgets = budgets
        self.transactions = transactions
        self.fixedCosts = fixedCosts
        self.savingsGoals = savingsGoals
        self.contributions = contributions
    }

    func encodedData() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) throws -> SharedBudgetAreaSnapshot {
        return try JSONDecoder().decode(Self.self, from: data)
    }

    func apply(to modelContext: ModelContext) throws -> BudgetGroup {
        let groupID = self.group.id
        let group = try modelContext.fetch(FetchDescriptor<BudgetGroup>(predicate: #Predicate { $0.id == groupID })).first ?? BudgetGroup()
        group.id = self.group.id
        group.name = self.group.name
        group.iconName = self.group.iconName
        group.iconColorHex = self.group.iconColorHex
        group.sortOrder = self.group.sortOrder
        group.isArchived = self.group.isArchived
        group.createdAt = self.group.createdAt
        group.updatedAt = self.group.updatedAt
        group.standardMonthlyBudget = self.group.standardMonthlyBudget
        if group.modelContext == nil { modelContext.insert(group) }

        for allocation in group.monthlyAllocations ?? [] { modelContext.delete(allocation) }
        for budget in group.budgets ?? [] { modelContext.delete(budget) }
        for fixedCost in group.fixedCosts ?? [] { modelContext.delete(fixedCost) }
        for goal in group.savingsGoals ?? [] { modelContext.delete(goal) }
        for transaction in group.transactions ?? [] { modelContext.delete(transaction) }

        let budgetMap = Dictionary(uniqueKeysWithValues: budgets.map { item in
            let budget = ElyraBudget.Budget(
                name: item.name,
                iconName: item.iconName,
                iconColorHex: item.iconColorHex,
                limit: item.limit,
                includesFixedCosts: item.includesFixedCosts,
                group: group,
                sortOrder: item.sortOrder,
                isArchived: item.isArchived
            )
            budget.id = item.id
            budget.createdAt = item.createdAt
            budget.updatedAt = item.updatedAt
            modelContext.insert(budget)
            return (item.id, budget)
        })

        for item in allocations {
            let allocation = BudgetGroupMonthlyAllocation(monthStart: item.monthStart, amount: item.amount, group: group)
            allocation.createdAt = item.createdAt
            allocation.updatedAt = item.updatedAt
            modelContext.insert(allocation)
        }

        let fixedCostMap: [UUID: ElyraBudget.FixedCost] = Dictionary(uniqueKeysWithValues: fixedCosts.map { item in
            let fixedCost = ElyraBudget.FixedCost(
                title: item.title,
                amount: item.amount,
                frequency: FixedCostFrequency(rawValue: item.frequencyRawValue) ?? .monthly,
                schedule: FixedCostSchedule(rawValue: item.scheduleRawValue) ?? .fixedDay,
                anchorDate: item.anchorDate,
                dayOfMonth: item.dayOfMonth,
                automaticBooking: item.automaticBooking,
                reminderEnabled: item.reminderEnabled,
                budget: item.budgetID.flatMap { budgetMap[$0] },
                group: group
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

        let goalMap: [UUID: ElyraBudget.SavingsGoal] = Dictionary(uniqueKeysWithValues: savingsGoals.map { item in
            let goal = ElyraBudget.SavingsGoal(
                name: item.name,
                type: SavingsGoalType(rawValue: item.typeRawValue) ?? .goal,
                targetAmount: item.targetAmount,
                targetDate: item.targetDate,
                contributionAmount: item.contributionAmount,
                frequency: SavingsFrequency(rawValue: item.frequencyRawValue) ?? .monthly,
                schedule: SavingsSchedule(rawValue: item.scheduleRawValue) ?? .fixedDay,
                anchorDate: item.anchorDate,
                automaticBooking: item.automaticBooking,
                budget: item.budgetID.flatMap { budgetMap[$0] },
                fixedCost: item.fixedCostID.flatMap { fixedCostMap[$0] },
                group: group
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

        for item in contributions {
            guard let goal = goalMap[item.goalID] else { continue }
            let contribution = SavingsContribution(
                amount: item.amount,
                date: item.date,
                note: item.note,
                automatic: item.automatic,
                occurrenceDate: item.occurrenceDate,
                goal: goal
            )
            contribution.id = item.id
            contribution.transactionID = item.transactionID
            modelContext.insert(contribution)
        }

        for item in transactions {
            let transaction = ElyraBudget.Transaction(
                title: item.title,
                amount: item.amount,
                date: item.date,
                note: item.note,
                type: TransactionType(rawValue: item.typeRawValue) ?? .expense,
                budget: item.budgetID.flatMap { budgetMap[$0] },
                group: group
            )
            transaction.id = item.id
            transaction.fixedCostID = item.fixedCostID
            transaction.fixedCostOccurrenceDate = item.fixedCostOccurrenceDate
            transaction.fixedCostBookingAutomatic = item.fixedCostBookingAutomatic
            transaction.savingsGoalCoveredAmount = item.savingsGoalCoveredAmount
            transaction.savingsGoalID = item.savingsGoalID
            transaction.savingsGoalOccurrenceDate = item.savingsGoalOccurrenceDate
            transaction.savingsContributionID = item.savingsContributionID
            modelContext.insert(transaction)
        }

        try modelContext.save()
        return group
    }
}
