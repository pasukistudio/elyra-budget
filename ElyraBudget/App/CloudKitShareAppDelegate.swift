import CloudKit
import Foundation
import os

#if os(iOS)
import UIKit

final class CloudKitShareAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = CloudKitShareSceneDelegate.self
        return configuration
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        Self.accept(metadata: metadata)
    }

    static func accept(metadata: CKShare.Metadata) {
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
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .elyraBudgetCloudKitShareAccepted,
                        object: nil
                    )
                }
            }
        }
        CKContainer(identifier: CloudKitSharedAreaService.containerIdentifier)
            .add(operation)
    }
}

final class CloudKitShareSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        CloudKitShareAppDelegate.accept(metadata: cloudKitShareMetadata)
    }
}
#endif
