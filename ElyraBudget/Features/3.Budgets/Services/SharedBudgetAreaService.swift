import Foundation
import CloudKit
import SwiftData
import os

@MainActor
final class CloudKitSharedAreaService {
    static let shared = CloudKitSharedAreaService()

    static let containerIdentifier = "iCloud.de.pasukistudio.elyrabudget"
    private let container = CKContainer(identifier: containerIdentifier)
    private let zoneID = CKRecordZone.ID(zoneName: "SharedBudgetAreas", ownerName: CKCurrentUserDefaultName)
    private let sharedAreaPrefix = "elyraBudget.cloudKitSharedArea."
    private let sharedAreaOwnerPrefix = "elyraBudget.cloudKitSharedAreaOwner."
    private let sharedAreaLastSyncPrefix = "elyraBudget.cloudKitSharedAreaLastSync."

    private init() {}

    static func recordDeletion(
        key: String,
        kind: SharedBudgetAreaRecordKind,
        groupID: UUID
    ) {
        SharedBudgetAreaDeletionStore.record(
            SharedBudgetAreaTombstone(key: key, kind: kind, deletedAt: .now),
            for: groupID
        )
    }

    static func allocationKey(for monthStart: Date) -> String {
        let normalized = Calendar.current.dateInterval(of: .month, for: monthStart)?.start ?? monthStart
        return String(normalized.timeIntervalSince1970)
    }

    static func isShared(groupID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: "elyraBudget.cloudKitSharedArea." + groupID.uuidString)
    }

    /// Marks an intentionally removed shared area as suppressed immediately.
    /// The CloudKit delete is retried separately so a transient network error
    /// cannot make the area reappear during the next discovery pass.
    static func suppressSharedArea(groupID: UUID) {
        let ownerName = UserDefaults.standard.string(forKey: sharedAreaOwnerKeyStatic(for: groupID))
        clearSharedAreaMetadata(for: groupID)
        if let ownerName {
            UserDefaults.standard.set(ownerName, forKey: sharedAreaOwnerKeyStatic(for: groupID))
        }
        UserDefaults.standard.set(
            true,
            forKey: "elyraBudget.cloudKitSharedAreaPendingDeletion." + groupID.uuidString
        )
    }

    static func retryPendingSharedAreaDeletions() async {
        let prefix = "elyraBudget.cloudKitSharedAreaPendingDeletion."
        let pendingIDs = UserDefaults.standard.dictionaryRepresentation().keys.compactMap { key -> UUID? in
            guard key.hasPrefix(prefix), UserDefaults.standard.bool(forKey: key) else { return nil }
            return UUID(uuidString: String(key.dropFirst(prefix.count)))
        }
        for groupID in pendingIDs {
            do {
                try await deleteSharedArea(groupID: groupID)
            } catch {
                AppLogger.persistence.error(
                    "Ausstehende Löschung eines geteilten Bereichs fehlgeschlagen: \(error.localizedDescription)"
                )
            }
        }
    }

    static func deleteSharedArea(groupID: UUID) async throws {
        guard isShared(groupID: groupID) || UserDefaults.standard.bool(
            forKey: "elyraBudget.cloudKitSharedAreaPendingDeletion." + groupID.uuidString
        ) || UserDefaults.standard.string(
            forKey: sharedAreaOwnerKeyStatic(for: groupID)
        ) != nil else { return }
        let ownerName = UserDefaults.standard.string(forKey: sharedAreaOwnerKeyStatic(for: groupID))
            ?? CKCurrentUserDefaultName
        guard ownerName == CKCurrentUserDefaultName else {
            // A participant cannot delete the owner's CloudKit root record.
            // Suppress the local copy and leave the invitation intact.
            clearSharedAreaMetadata(for: groupID)
            clearPendingDeletion(for: groupID)
            return
        }
        let (database, recordID) = databaseAndRecordIDStatic(for: groupID)

        let root: CKRecord
        do {
            root = try await shared.retryingCloudKitOperation {
                try await database.record(for: recordID)
            }
        } catch let error as CKError where error.code == .unknownItem {
            clearSharedAreaMetadata(for: groupID)
            clearPendingDeletion(for: groupID)
            return
        }

        var recordIDs = [recordID]
        if let shareReference = root.share {
            recordIDs.append(shareReference.recordID)
        }
        _ = try await shared.retryingCloudKitOperation {
            try await database.modifyRecords(saving: [], deleting: recordIDs)
        }
        clearSharedAreaMetadata(for: groupID)
        clearPendingDeletion(for: groupID)
    }

    private static func sharedAreaOwnerKeyStatic(for groupID: UUID) -> String {
        "elyraBudget.cloudKitSharedAreaOwner." + groupID.uuidString
    }

    private static func databaseAndRecordIDStatic(for groupID: UUID) -> (CKDatabase, CKRecord.ID) {
        let ownerName = UserDefaults.standard.string(forKey: sharedAreaOwnerKeyStatic(for: groupID)) ?? CKCurrentUserDefaultName
        let zoneID = CKRecordZone.ID(zoneName: "SharedBudgetAreas", ownerName: ownerName)
        let database: CKDatabase = ownerName == CKCurrentUserDefaultName
            ? shared.container.privateCloudDatabase
            : shared.container.sharedCloudDatabase
        return (database, CKRecord.ID(recordName: groupID.uuidString, zoneID: zoneID))
    }

    private static func clearSharedAreaMetadata(for groupID: UUID) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "elyraBudget.cloudKitSharedArea." + groupID.uuidString)
        defaults.removeObject(forKey: sharedAreaOwnerKeyStatic(for: groupID))
        defaults.removeObject(forKey: "elyraBudget.cloudKitSharedAreaLastSync." + groupID.uuidString)
        defaults.set(true, forKey: "elyraBudget.cloudKitSharedAreaSuppressed." + groupID.uuidString)
    }

    private static func clearPendingDeletion(for groupID: UUID) {
        UserDefaults.standard.removeObject(
            forKey: "elyraBudget.cloudKitSharedAreaPendingDeletion." + groupID.uuidString
        )
    }

    func prepareShare(for group: BudgetGroup) async throws -> CKShare {
        UserDefaults.standard.removeObject(
            forKey: "elyraBudget.cloudKitSharedAreaSuppressed." + group.id.uuidString
        )
        Self.clearPendingDeletion(for: group.id)
        let database = container.privateCloudDatabase
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await database.modifyRecordZones(saving: [zone], deleting: [])

        let recordID = CKRecord.ID(recordName: group.id.uuidString, zoneID: zoneID)
        let root: CKRecord
        do {
            root = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            root = CKRecord(recordType: "SharedBudgetArea", recordID: recordID)
        }

        let localSnapshot = SharedBudgetAreaSnapshot(group: group)
        let snapshot: SharedBudgetAreaSnapshot
        if let remoteData = root["payload"] as? Data,
           let remoteSnapshot = try? SharedBudgetAreaSnapshot.decode(remoteData) {
            // Re-opening the sharing UI must not publish a stale local graph
            // over edits that were already made by the other participant.
            snapshot = remoteSnapshot.merged(with: localSnapshot)
        } else {
            snapshot = localSnapshot
        }

        root["groupID"] = group.id.uuidString as CKRecordValue
        root["name"] = snapshot.group.name as CKRecordValue
        root["payload"] = try snapshot.encodedData() as CKRecordValue
        root["updatedAt"] = Date() as CKRecordValue

        let share: CKShare
        if let shareReference = root.share {
            guard let existingShare = try await database.record(for: shareReference.recordID) as? CKShare else {
                throw SharedBudgetAreaError.invalidShareRecord
            }
            share = existingShare
        } else {
            share = CKShare(rootRecord: root)
            share[CKShare.SystemFieldKey.title] = snapshot.group.name as CKRecordValue
            share.publicPermission = .none
        }

        let syncDate = Date()
        root["updatedAt"] = syncDate as CKRecordValue
        _ = try await database.modifyRecords(saving: [root, share], deleting: [])
        UserDefaults.standard.set(true, forKey: sharedAreaKey(for: group.id))
        UserDefaults.standard.set(zoneID.ownerName, forKey: sharedAreaOwnerKey(for: group.id))
        setLastSyncDate(syncDate, for: group.id)
        return share
    }

    func importAcceptedShare(
        metadata: CKShare.Metadata,
        modelContext: ModelContext
    ) async throws -> BudgetGroup {
        guard let rootRecordID = metadata.hierarchicalRootRecordID else {
            throw SharedBudgetAreaError.invalidShareRecord
        }
        let record = try await fetchSharedRecord(recordID: rootRecordID)
        guard let data = record["payload"] as? Data else {
            throw SharedBudgetAreaError.unsupportedPayload
        }
        let remoteSnapshot = try SharedBudgetAreaSnapshot.decode(data)
        let localGroup = try modelContext.fetch(
            FetchDescriptor<BudgetGroup>(predicate: #Predicate { $0.id == remoteSnapshot.group.id })
        ).first
        let snapshot = localGroup.map {
            remoteSnapshot.merged(with: SharedBudgetAreaSnapshot(group: $0))
        } ?? remoteSnapshot
        let group = try snapshot.apply(to: modelContext)
        UserDefaults.standard.removeObject(
            forKey: "elyraBudget.cloudKitSharedAreaSuppressed." + group.id.uuidString
        )
        UserDefaults.standard.set(true, forKey: sharedAreaKey(for: group.id))
        UserDefaults.standard.set(
            rootRecordID.zoneID.ownerName,
            forKey: sharedAreaOwnerKey(for: group.id)
        )
        setLastSyncDate(record["updatedAt"] as? Date ?? .now, for: group.id)
        try modelContext.save()
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
        let record: CKRecord
        do {
            record = try await fetchSharedRecord(recordID: recordID)
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            // The invitation may have been revoked or its area deleted. Do
            // not let that stale pointer block discovery of newer invitations.
            clearPendingShareDefaults()
            return nil
        }
        guard let data = record["payload"] as? Data else {
            throw SharedBudgetAreaError.unsupportedPayload
        }
        let remoteSnapshot = try SharedBudgetAreaSnapshot.decode(data)
        let localGroup = try modelContext.fetch(
            FetchDescriptor<BudgetGroup>(predicate: #Predicate { $0.id == remoteSnapshot.group.id })
        ).first
        let snapshot = localGroup.map {
            remoteSnapshot.merged(with: SharedBudgetAreaSnapshot(group: $0))
        } ?? remoteSnapshot
        let group = try snapshot.apply(to: modelContext)
        defaults.removeObject(
            forKey: "elyraBudget.cloudKitSharedAreaSuppressed." + group.id.uuidString
        )
        defaults.set(true, forKey: sharedAreaKey(for: group.id))
        defaults.set(ownerName, forKey: sharedAreaOwnerKey(for: group.id))
        setLastSyncDate(record["updatedAt"] as? Date ?? .now, for: group.id)
        try modelContext.save()
        clearPendingShareDefaults()
        return group
    }

    private func clearPendingShareDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "elyraBudget.pendingCloudKitShare.recordName")
        defaults.removeObject(forKey: "elyraBudget.pendingCloudKitShare.zoneName")
        defaults.removeObject(forKey: "elyraBudget.pendingCloudKitShare.ownerName")
        defaults.removeObject(forKey: "elyraBudget.pendingCloudKitShare.failed")
    }

    /// Recovers shared areas when iOS did not deliver the share-accept callback
    /// to the app, for example after accepting an invitation from Settings.
    /// The shared database is the source of truth for invitations already
    /// accepted by the current iCloud account.
    func discoverAndImportSharedAreas(modelContext: ModelContext) async throws -> [BudgetGroup] {
        let database = container.sharedCloudDatabase
        let zones = try await retryingCloudKitOperation {
            try await database.allRecordZones()
        }
        var importedGroups: [BudgetGroup] = []

        for zone in zones where zone.zoneID.zoneName == zoneID.zoneName {
            let query = CKQuery(
                recordType: "SharedBudgetArea",
                predicate: NSPredicate(value: true)
            )
            let (matches, _) = try await retryingCloudKitOperation {
                try await database.records(
                    matching: query,
                    inZoneWith: zone.zoneID
                )
            }

            for (_, result) in matches {
                guard case .success(let record) = result else {
                    if case .failure(let error) = result {
                        AppLogger.persistence.error(
                            "CloudKit-Bereichsdatensatz konnte nicht gelesen werden: \(error.localizedDescription)"
                        )
                    }
                    continue
                }
                guard let data = record["payload"] as? Data else {
                    AppLogger.persistence.error(
                        "CloudKit-Bereichsdatensatz enthält kein gültiges Payload."
                    )
                    continue
                }

                let snapshot = try SharedBudgetAreaSnapshot.decode(data)
                let groupID = snapshot.group.id
                if UserDefaults.standard.bool(
                    forKey: "elyraBudget.cloudKitSharedAreaSuppressed." + groupID.uuidString
                ) {
                    continue
                }
                let existingGroup = try modelContext.fetch(
                    FetchDescriptor<BudgetGroup>(
                        predicate: #Predicate { $0.id == groupID }
                    )
                ).first
                if let existingGroup {
                    UserDefaults.standard.set(true, forKey: sharedAreaKey(for: groupID))
                    UserDefaults.standard.set(
                        zone.zoneID.ownerName,
                        forKey: sharedAreaOwnerKey(for: groupID)
                    )
                    setLastSyncDate(record["updatedAt"] as? Date ?? .now, for: groupID)
                    importedGroups.append(existingGroup)
                    continue
                }

                let group = try snapshot.apply(to: modelContext)
                UserDefaults.standard.set(true, forKey: sharedAreaKey(for: group.id))
                UserDefaults.standard.set(
                    zone.zoneID.ownerName,
                    forKey: sharedAreaOwnerKey(for: group.id)
                )
                setLastSyncDate(record["updatedAt"] as? Date ?? .now, for: group.id)
                importedGroups.append(group)
            }
        }

        return importedGroups
    }

    func updateSharedArea(
        group: BudgetGroup
    ) async throws {
        guard UserDefaults.standard.bool(forKey: sharedAreaKey(for: group.id)) else { return }
        let (database, recordID) = databaseAndRecordID(for: group.id)
        let record = try await retryingCloudKitOperation {
            try await database.record(for: recordID)
        }
        try await upload(group: group, record: record, database: database)
    }

    func pullSharedArea(
        group: BudgetGroup,
        modelContext: ModelContext
    ) async throws {
        guard UserDefaults.standard.bool(forKey: sharedAreaKey(for: group.id)) else { return }
        let (database, recordID) = databaseAndRecordID(for: group.id)
        let record = try await retryingCloudKitOperation {
            try await database.record(for: recordID)
        }
        let remoteUpdatedAt = record["updatedAt"] as? Date ?? .distantPast
        let lastSyncDate = lastSyncDate(for: group.id)
        let localModifiedAt = latestLocalModification(for: group)

        if localModifiedAt > remoteUpdatedAt.addingTimeInterval(0.5) {
            try await upload(group: group, record: record, database: database)
            return
        }

        if let lastSyncDate,
           remoteUpdatedAt <= lastSyncDate.addingTimeInterval(0.5) {
            return
        }

        guard let data = record["payload"] as? Data else {
            throw SharedBudgetAreaError.unsupportedPayload
        }
        let remoteSnapshot = try SharedBudgetAreaSnapshot.decode(data)
        let mergedSnapshot = remoteSnapshot.merged(with: SharedBudgetAreaSnapshot(group: group))
        _ = try mergedSnapshot.apply(to: modelContext)
        setLastSyncDate(remoteUpdatedAt, for: group.id)

        // If this device had records that were not part of the remote
        // snapshot, publish the merged result so both users converge on the
        // same complete set of records.
        if try mergedSnapshot.encodedData() != data {
            let mergedRecord = try await retryingCloudKitOperation {
                try await database.record(for: recordID)
            }
            try await upload(
                snapshot: mergedSnapshot,
                groupID: group.id,
                groupName: mergedSnapshot.group.name,
                record: mergedRecord,
                database: database
            )
        }
    }

    private func sharedAreaKey(for groupID: UUID) -> String {
        sharedAreaPrefix + groupID.uuidString
    }

    private func sharedAreaOwnerKey(for groupID: UUID) -> String {
        sharedAreaOwnerPrefix + groupID.uuidString
    }

    private func sharedAreaLastSyncKey(for groupID: UUID) -> String {
        sharedAreaLastSyncPrefix + groupID.uuidString
    }

    private func lastSyncDate(for groupID: UUID) -> Date? {
        let value = UserDefaults.standard.double(forKey: sharedAreaLastSyncKey(for: groupID))
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    private func setLastSyncDate(_ date: Date, for groupID: UUID) {
        UserDefaults.standard.set(
            date.timeIntervalSince1970,
            forKey: sharedAreaLastSyncKey(for: groupID)
        )
    }

    private func latestLocalModification(for group: BudgetGroup) -> Date {
        var latest = group.updatedAt
        if let tombstoneDate = SharedBudgetAreaDeletionStore.load(for: group.id)
            .map(\.deletedAt)
            .max(), tombstoneDate > latest {
            latest = tombstoneDate
        }
        let dates = (group.monthlyAllocations ?? []).map(\.updatedAt)
            + (group.budgets ?? []).map(\.updatedAt)
            + (group.fixedCosts ?? []).map(\.updatedAt)
            + (group.savingsGoals ?? []).map(\.updatedAt)
            + (group.transactions ?? []).map(\.updatedAt)

        if let date = dates.max(), date > latest {
            latest = date
        }

        for contribution in (group.savingsGoals ?? []).flatMap({ $0.contributions ?? [] }) {
            if contribution.date > latest {
                latest = contribution.date
            }
            if contribution.updatedAt > latest {
                latest = contribution.updatedAt
            }
        }
        return latest
    }

    private func upload(
        group: BudgetGroup,
        record: CKRecord,
        database: CKDatabase
    ) async throws {
        let localSnapshot = SharedBudgetAreaSnapshot(group: group)
        let mergedSnapshot: SharedBudgetAreaSnapshot
        if let remoteData = record["payload"] as? Data,
           let remoteSnapshot = try? SharedBudgetAreaSnapshot.decode(remoteData) {
            mergedSnapshot = remoteSnapshot.merged(with: localSnapshot)
        } else {
            mergedSnapshot = localSnapshot
        }
        try await upload(
            snapshot: mergedSnapshot,
            groupID: group.id,
            groupName: mergedSnapshot.group.name,
            record: record,
            database: database
        )
    }

    private func upload(
        snapshot: SharedBudgetAreaSnapshot,
        groupID: UUID,
        groupName: String,
        record: CKRecord,
        database: CKDatabase
    ) async throws {
        var candidate = record
        var candidateSnapshot = snapshot

        for attempt in 0..<5 {
            let syncDate = Date()
            candidate["name"] = groupName as CKRecordValue
            candidate["payload"] = try candidateSnapshot.encodedData() as CKRecordValue
            candidate["updatedAt"] = syncDate as CKRecordValue

            do {
                _ = try await retryingCloudKitOperation {
                    try await database.modifyRecords(saving: [candidate], deleting: [])
                }
                setLastSyncDate(syncDate, for: groupID)
                return
            } catch let error as CKError where error.code == .serverRecordChanged && attempt < 4 {
                // Another device committed between our fetch and save. Merge
                // against Apple's current server record and retry with its
                // change tag instead of overwriting the other user's edit.
                guard let serverRecord = error.serverRecord
                    ?? error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord else {
                    throw error
                }
                if let remoteData = serverRecord["payload"] as? Data,
                   let remoteSnapshot = try? SharedBudgetAreaSnapshot.decode(remoteData) {
                    candidateSnapshot = remoteSnapshot.merged(with: candidateSnapshot)
                }
                candidate = serverRecord
            }
        }
    }

    private func databaseAndRecordID(for groupID: UUID) -> (CKDatabase, CKRecord.ID) {
        let ownerName = UserDefaults.standard.string(
            forKey: sharedAreaOwnerKey(for: groupID)
        ) ?? CKCurrentUserDefaultName
        let recordZoneID = CKRecordZone.ID(
            zoneName: zoneID.zoneName,
            ownerName: ownerName
        )
        let database: CKDatabase = ownerName == CKCurrentUserDefaultName
            ? container.privateCloudDatabase
            : container.sharedCloudDatabase
        return (
            database,
            CKRecord.ID(recordName: groupID.uuidString, zoneID: recordZoneID)
        )
    }

    private func fetchSharedRecord(recordID: CKRecord.ID) async throws -> CKRecord {
        try await retryingCloudKitOperation {
            try await container.sharedCloudDatabase.record(for: recordID)
        }
    }

    private func retryingCloudKitOperation<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        let maximumAttempts = 5
        var attempt = 0

        while true {
            do {
                return try await operation()
            } catch let error as CKError
                where Self.isRetryableCloudKitError(error) && attempt < maximumAttempts - 1 {
                attempt += 1
                let delay = error.retryAfterSeconds ?? Double(attempt)
                try await Task.sleep(for: .seconds(max(1, delay)))
            }
        }
    }

    private static func isRetryableCloudKitError(_ error: CKError) -> Bool {
        switch error.code {
        case .networkUnavailable,
             .networkFailure,
             .serviceUnavailable,
             .requestRateLimited,
             .zoneBusy,
             .zoneNotFound,
             .unknownItem:
            return true
        default:
            return false
        }
    }
}

extension Notification.Name {
    static let elyraBudgetCloudKitShareAccepted = Notification.Name(
        "elyraBudget.cloudKitShareAccepted"
    )
}

enum SharedBudgetAreaRecordKind: String, Codable {
    case allocation
    case budget
    case transaction
    case fixedCost
    case savingsGoal
    case contribution
}

struct SharedBudgetAreaTombstone: Codable, Hashable {
    let key: String
    let kind: SharedBudgetAreaRecordKind
    let deletedAt: Date
}

private enum SharedBudgetAreaDeletionStore {
    private static let prefix = "elyraBudget.cloudKitSharedAreaTombstones."

    static func record(_ tombstone: SharedBudgetAreaTombstone, for groupID: UUID) {
        var tombstones = load(for: groupID)
        tombstones.removeAll { $0.key == tombstone.key && $0.kind == tombstone.kind }
        tombstones.append(tombstone)
        if let data = try? JSONEncoder().encode(tombstones) {
            UserDefaults.standard.set(data, forKey: prefix + groupID.uuidString)
        }
    }

    static func load(for groupID: UUID) -> [SharedBudgetAreaTombstone] {
        guard let data = UserDefaults.standard.data(forKey: prefix + groupID.uuidString),
              let tombstones = try? JSONDecoder().decode([SharedBudgetAreaTombstone].self, from: data) else {
            return []
        }
        return tombstones
    }

    static func latestDate(for groupID: UUID) -> Date? {
        load(for: groupID).map(\.deletedAt).max()
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
        let greenBudgetThreshold: Int?
        let orangeBudgetThreshold: Int?
        // Optional for backwards compatibility with older shared payloads.
        let roundUpTransactionsEnabled: Bool?
        let roundUpReserveID: UUID?
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
        // Optional keeps snapshots created by older app versions readable.
        let updatedAt: Date?
        let receiptFilename: String?
        let receiptData: Data?
        let roundUpOriginalAmount: Decimal?
        let roundUpSavingsContributionID: UUID?
        let createdAt: Date?
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
        // Optional keeps snapshots created before contribution timestamps readable.
        let updatedAt: Date?
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
    // Optional keeps snapshots created before tombstones were introduced readable.
    let tombstones: [SharedBudgetAreaTombstone]?

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
            standardMonthlyBudget: group.standardMonthlyBudget,
            greenBudgetThreshold: group.greenBudgetThreshold,
            orangeBudgetThreshold: group.orangeBudgetThreshold,
            roundUpTransactionsEnabled: group.roundUpTransactionsEnabled,
            roundUpReserveID: group.roundUpReserveID
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
                budgetID: $0.budget?.id,
                updatedAt: $0.updatedAt,
                receiptFilename: $0.receiptFilename,
                receiptData: $0.receiptData,
                roundUpOriginalAmount: $0.roundUpOriginalAmount,
                roundUpSavingsContributionID: $0.roundUpSavingsContributionID,
                createdAt: $0.createdAt
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
                    updatedAt: $0.updatedAt,
                    note: $0.note,
                    automatic: $0.automatic,
                    occurrenceDate: $0.occurrenceDate,
                    transactionID: $0.transactionID,
                    goalID: goal.id
                )
            }
        }
        let liveKeys: Set<String> = Set(
            (group.monthlyAllocations ?? []).map {
                "allocation:\(CloudKitSharedAreaService.allocationKey(for: $0.monthStart))"
            }
            + (group.budgets ?? []).map { "budget:\($0.id.uuidString)" }
            + (group.transactions ?? []).map { "transaction:\($0.id.uuidString)" }
            + (group.fixedCosts ?? []).map { "fixedCost:\($0.id.uuidString)" }
            + (group.savingsGoals ?? []).map { "savingsGoal:\($0.id.uuidString)" }
            + (group.savingsGoals ?? []).flatMap { goal in
                (goal.contributions ?? []).map { "contribution:\($0.id.uuidString)" }
            }
        )
        // A failed local save can leave a deleted object in the context. Do
        // not publish its tombstone while the object is still present.
        self.tombstones = SharedBudgetAreaDeletionStore.load(for: group.id).filter {
            !liveKeys.contains("\($0.kind.rawValue):\($0.key)")
        }
    }

    private init(
        group: Group,
        allocations: [Allocation],
        budgets: [Budget],
        transactions: [Transaction],
        fixedCosts: [FixedCost],
        savingsGoals: [SavingsGoal],
        contributions: [Contribution],
        tombstones: [SharedBudgetAreaTombstone]
    ) {
        self.group = group
        self.allocations = allocations
        self.budgets = budgets
        self.transactions = transactions
        self.fixedCosts = fixedCosts
        self.savingsGoals = savingsGoals
        self.contributions = contributions
        self.tombstones = tombstones
    }

    private var effectiveTombstones: [SharedBudgetAreaTombstone] {
        tombstones ?? []
    }

    /// Merges two complete snapshots without losing records created on the
    /// other device. `self` is the remote snapshot and `other` is local.
    /// Records with the same identifier use the newest modification date;
    /// local data wins ties so a just-created local record is retained.
    func merged(with other: SharedBudgetAreaSnapshot) -> SharedBudgetAreaSnapshot {
        let mergedGroup = other.group.updatedAt >= group.updatedAt ? other.group : group
        let mergedTombstones = Self.mergeTombstones(
            remote: effectiveTombstones,
            local: other.effectiveTombstones
        )

        return SharedBudgetAreaSnapshot(
            group: mergedGroup,
            allocations: Self.merge(
                remote: allocations,
                local: other.allocations,
                key: { $0.monthStart },
                modified: { $0.updatedAt }
            ).filter { !Self.isDeleted($0.monthStart, kind: .allocation, tombstones: mergedTombstones, modified: $0.updatedAt) },
            budgets: Self.merge(
                remote: budgets,
                local: other.budgets,
                key: { $0.id },
                modified: { $0.updatedAt }
            ).filter { !Self.isDeleted($0.id.uuidString, kind: .budget, tombstones: mergedTombstones, modified: $0.updatedAt) },
            transactions: Self.merge(
                remote: transactions,
                local: other.transactions,
                key: { $0.id },
                modified: { $0.updatedAt ?? $0.date }
            ).filter { !Self.isDeleted($0.id.uuidString, kind: .transaction, tombstones: mergedTombstones, modified: $0.updatedAt ?? $0.date) },
            fixedCosts: Self.merge(
                remote: fixedCosts,
                local: other.fixedCosts,
                key: { $0.id },
                modified: { $0.updatedAt }
            ).filter { !Self.isDeleted($0.id.uuidString, kind: .fixedCost, tombstones: mergedTombstones, modified: $0.updatedAt) },
            savingsGoals: Self.merge(
                remote: savingsGoals,
                local: other.savingsGoals,
                key: { $0.id },
                modified: { $0.updatedAt }
            ).filter { !Self.isDeleted($0.id.uuidString, kind: .savingsGoal, tombstones: mergedTombstones, modified: $0.updatedAt) },
            contributions: Self.merge(
                remote: contributions,
                local: other.contributions,
                key: { $0.id },
                modified: { $0.updatedAt ?? $0.date }
            ).filter { !Self.isDeleted($0.id.uuidString, kind: .contribution, tombstones: mergedTombstones, modified: $0.updatedAt ?? $0.date) },
            tombstones: mergedTombstones
        )
    }

    private static func mergeTombstones(
        remote: [SharedBudgetAreaTombstone],
        local: [SharedBudgetAreaTombstone]
    ) -> [SharedBudgetAreaTombstone] {
        var merged: [String: SharedBudgetAreaTombstone] = [:]
        for tombstone in remote + local {
            let key = tombstone.kind.rawValue + ":" + tombstone.key
            if merged[key]?.deletedAt ?? .distantPast <= tombstone.deletedAt {
                merged[key] = tombstone
            }
        }
        return merged.values.sorted { $0.deletedAt < $1.deletedAt }
    }

    private static func isDeleted(
        _ key: String,
        kind: SharedBudgetAreaRecordKind,
        tombstones: [SharedBudgetAreaTombstone],
        modified: Date
    ) -> Bool {
        guard let tombstone = tombstones.last(where: { $0.key == key && $0.kind == kind }) else {
            return false
        }
        return tombstone.deletedAt >= modified
    }

    private static func isDeleted(
        _ monthStart: Date,
        kind: SharedBudgetAreaRecordKind,
        tombstones: [SharedBudgetAreaTombstone],
        modified: Date
    ) -> Bool {
        let key = String((Calendar.current.dateInterval(of: .month, for: monthStart)?.start ?? monthStart).timeIntervalSince1970)
        return isDeleted(key, kind: kind, tombstones: tombstones, modified: modified)
    }

    private static func merge<Item, Key: Hashable>(
        remote: [Item],
        local: [Item],
        key: (Item) -> Key,
        modified: (Item) -> Date
    ) -> [Item] {
        var merged = Dictionary(uniqueKeysWithValues: remote.map { (key($0), $0) })

        for item in local {
            guard let existing = merged[key(item)] else {
                merged[key(item)] = item
                continue
            }
            if modified(item) >= modified(existing) {
                merged[key(item)] = item
            }
        }

        return merged.values.sorted {
            String(describing: key($0)) < String(describing: key($1))
        }
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
        group.greenBudgetThreshold = self.group.greenBudgetThreshold ?? 70
        group.orangeBudgetThreshold = self.group.orangeBudgetThreshold ?? 100
        group.roundUpTransactionsEnabled = self.group.roundUpTransactionsEnabled ?? false
        group.roundUpReserveID = self.group.roundUpReserveID
        if group.modelContext == nil { modelContext.insert(group) }

        for tombstone in effectiveTombstones {
            switch tombstone.kind {
            case .allocation:
                for allocation in (group.monthlyAllocations ?? []) where
                    CloudKitSharedAreaService.allocationKey(for: allocation.monthStart) == tombstone.key &&
                    tombstone.deletedAt >= allocation.updatedAt {
                    modelContext.delete(allocation)
                }
            case .budget:
                for budget in (group.budgets ?? []) where
                    budget.id.uuidString == tombstone.key && tombstone.deletedAt >= budget.updatedAt {
                    modelContext.delete(budget)
                }
            case .transaction:
                for transaction in (group.transactions ?? []) where
                    transaction.id.uuidString == tombstone.key && tombstone.deletedAt >= transaction.updatedAt {
                    modelContext.delete(transaction)
                }
            case .fixedCost:
                for fixedCost in (group.fixedCosts ?? []) where
                    fixedCost.id.uuidString == tombstone.key && tombstone.deletedAt >= fixedCost.updatedAt {
                    modelContext.delete(fixedCost)
                }
            case .savingsGoal:
                for goal in (group.savingsGoals ?? []) where
                    goal.id.uuidString == tombstone.key && tombstone.deletedAt >= goal.updatedAt {
                    modelContext.delete(goal)
                }
            case .contribution:
                for goal in (group.savingsGoals ?? []) {
                    for contribution in (goal.contributions ?? []) where
                        contribution.id.uuidString == tombstone.key && tombstone.deletedAt >= contribution.updatedAt {
                        modelContext.delete(contribution)
                    }
                }
            }
        }

        // Never replace the complete child graph on a pull. A replacement
        // would delete receipts and locally-created records when the other
        // device uploads an older snapshot. Update by stable IDs instead and
        // keep records absent from an older payload until an explicit delete
        // protocol exists.
        var budgetMap = Dictionary(uniqueKeysWithValues: (group.budgets ?? []).map { ($0.id, $0) })
        for item in budgets {
            let budget = budgetMap[item.id] ?? ElyraBudget.Budget(group: group)
            budget.id = item.id
            budget.name = item.name
            budget.iconName = item.iconName
            budget.iconColorHex = item.iconColorHex
            budget.limit = item.limit
            budget.includesFixedCosts = item.includesFixedCosts
            budget.group = group
            budget.sortOrder = item.sortOrder
            budget.isArchived = item.isArchived
            budget.createdAt = item.createdAt
            budget.updatedAt = item.updatedAt
            if budget.modelContext == nil { modelContext.insert(budget) }
            budgetMap[item.id] = budget
        }

        for item in allocations {
            let normalizedMonth = Calendar.current.dateInterval(of: .month, for: item.monthStart)?.start ?? item.monthStart
            let allocation = (group.monthlyAllocations ?? []).first {
                let existingMonth = Calendar.current.dateInterval(of: .month, for: $0.monthStart)?.start ?? $0.monthStart
                return existingMonth == normalizedMonth
            } ?? BudgetGroupMonthlyAllocation(monthStart: normalizedMonth, amount: item.amount, group: group)
            allocation.group = group
            allocation.monthStart = normalizedMonth
            allocation.amount = item.amount
            allocation.createdAt = item.createdAt
            allocation.updatedAt = item.updatedAt
            if allocation.modelContext == nil { modelContext.insert(allocation) }
        }

        var fixedCostMap = Dictionary(uniqueKeysWithValues: (group.fixedCosts ?? []).map { ($0.id, $0) })
        for item in fixedCosts {
            let fixedCost = fixedCostMap[item.id] ?? ElyraBudget.FixedCost(group: group)
            fixedCost.id = item.id
            fixedCost.title = item.title
            fixedCost.amount = item.amount
            fixedCost.frequencyRawValue = item.frequencyRawValue
            fixedCost.scheduleRawValue = item.scheduleRawValue
            fixedCost.anchorDate = item.anchorDate
            fixedCost.configurationEffectiveDate = item.configurationEffectiveDate
            fixedCost.dayOfMonth = item.dayOfMonth
            fixedCost.automaticBooking = item.automaticBooking
            fixedCost.reminderEnabled = item.reminderEnabled
            fixedCost.isPaused = item.isPaused
            fixedCost.pauseUntil = item.pauseUntil
            fixedCost.note = item.note
            fixedCost.budget = item.budgetID.flatMap { budgetMap[$0] }
            fixedCost.group = group
            fixedCost.createdAt = item.createdAt
            fixedCost.updatedAt = item.updatedAt
            if fixedCost.modelContext == nil { modelContext.insert(fixedCost) }
            fixedCostMap[item.id] = fixedCost
        }

        var goalMap = Dictionary(uniqueKeysWithValues: (group.savingsGoals ?? []).map { ($0.id, $0) })
        for item in savingsGoals {
            let goal = goalMap[item.id] ?? ElyraBudget.SavingsGoal(group: group)
            goal.id = item.id
            goal.name = item.name
            goal.typeRawValue = item.typeRawValue
            goal.targetAmount = item.targetAmount
            goal.targetDate = item.targetDate
            goal.contributionAmount = item.contributionAmount
            goal.frequencyRawValue = item.frequencyRawValue
            goal.scheduleRawValue = item.scheduleRawValue
            goal.anchorDate = item.anchorDate
            goal.dayOfMonth = item.dayOfMonth
            goal.automaticBooking = item.automaticBooking
            goal.note = item.note
            goal.iconName = item.iconName
            goal.iconColorHex = item.iconColorHex
            goal.sortOrder = item.sortOrder
            goal.isArchived = item.isArchived
            goal.budget = item.budgetID.flatMap { budgetMap[$0] }
            goal.fixedCost = item.fixedCostID.flatMap { fixedCostMap[$0] }
            goal.group = group
            goal.createdAt = item.createdAt
            goal.updatedAt = item.updatedAt
            if goal.modelContext == nil { modelContext.insert(goal) }
            goalMap[item.id] = goal
        }

        for item in contributions {
            guard let goal = goalMap[item.goalID] else { continue }
            let contribution = (goal.contributions ?? []).first { $0.id == item.id }
                ?? SavingsContribution(amount: item.amount, goal: goal)
            contribution.id = item.id
            contribution.amount = item.amount
            contribution.date = item.date
            contribution.updatedAt = item.updatedAt ?? item.date
            contribution.note = item.note
            contribution.automatic = item.automatic
            contribution.occurrenceDate = item.occurrenceDate
            contribution.goal = goal
            contribution.transactionID = item.transactionID
            if contribution.modelContext == nil { modelContext.insert(contribution) }
        }

        for item in transactions {
            let transaction = (group.transactions ?? []).first { $0.id == item.id }
                ?? ElyraBudget.Transaction(group: group)
            transaction.id = item.id
            transaction.title = item.title
            transaction.amount = item.amount
            transaction.date = item.date
            transaction.note = item.note
            transaction.typeRawValue = item.typeRawValue
            transaction.budget = item.budgetID.flatMap { budgetMap[$0] }
            transaction.group = group
            transaction.fixedCostID = item.fixedCostID
            transaction.fixedCostOccurrenceDate = item.fixedCostOccurrenceDate
            transaction.fixedCostBookingAutomatic = item.fixedCostBookingAutomatic
            transaction.savingsGoalCoveredAmount = item.savingsGoalCoveredAmount
            transaction.savingsGoalID = item.savingsGoalID
            transaction.savingsGoalOccurrenceDate = item.savingsGoalOccurrenceDate
            transaction.savingsContributionID = item.savingsContributionID
            // Older payloads do not contain these fields. Keep the local
            // value in that case instead of interpreting a missing field as
            // an instruction to erase a receipt or round-up relation.
            if item.updatedAt != nil {
                transaction.receiptFilename = item.receiptFilename
                transaction.receiptData = item.receiptData
            }
            // `updatedAt == nil` identifies a legacy payload. Current
            // snapshots must be allowed to clear an optional round-up link;
            // otherwise a deletion on one device survives on the other.
            if item.updatedAt != nil {
                transaction.roundUpOriginalAmount = item.roundUpOriginalAmount
                transaction.roundUpSavingsContributionID = item.roundUpSavingsContributionID
            }
            transaction.createdAt = item.createdAt ?? transaction.createdAt
            transaction.updatedAt = item.updatedAt ?? item.date
            if transaction.modelContext == nil { modelContext.insert(transaction) }
        }

        try modelContext.save()
        return group
    }
}
