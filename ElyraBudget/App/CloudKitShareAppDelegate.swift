import CloudKit
import os

#if os(iOS)
import UIKit

final class CloudKitShareAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        guard let recordID = metadata.hierarchicalRootRecordID else {
            AppLogger.persistence.error("CloudKit-Bereich enthält keine Root-Record-ID.")
            return
        }
        let defaults = UserDefaults.standard
        defaults.set(recordID.recordName, forKey: "elyraBudget.pendingCloudKitShare.recordName")
        defaults.set(recordID.zoneID.zoneName, forKey: "elyraBudget.pendingCloudKitShare.zoneName")
        defaults.set(recordID.zoneID.ownerName, forKey: "elyraBudget.pendingCloudKitShare.ownerName")

        let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
        operation.acceptSharesResultBlock = { result in
            if case .failure(let error) = result {
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
#endif
