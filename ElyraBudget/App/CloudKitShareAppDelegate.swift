import CloudKit
import os
import UIKit

final class CloudKitShareAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        let recordID = metadata.rootRecordID
        let defaults = UserDefaults.standard
        defaults.set(recordID.recordName, forKey: "elyraBudget.pendingCloudKitShare.recordName")
        defaults.set(recordID.zoneID.zoneName, forKey: "elyraBudget.pendingCloudKitShare.zoneName")
        defaults.set(recordID.zoneID.ownerName, forKey: "elyraBudget.pendingCloudKitShare.ownerName")

        let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
        operation.acceptSharesCompletionBlock = { error in
            if let error {
                AppLogger.persistence.error("CloudKit-Bereich konnte nicht angenommen werden: \(error.localizedDescription)")
                defaults.set(true, forKey: "elyraBudget.pendingCloudKitShare.failed")
            } else {
                defaults.set(false, forKey: "elyraBudget.pendingCloudKitShare.failed")
            }
        }
        CKContainer(identifier: CloudKitSharedAreaService.containerIdentifier)
            .add(operation)
    }
}
