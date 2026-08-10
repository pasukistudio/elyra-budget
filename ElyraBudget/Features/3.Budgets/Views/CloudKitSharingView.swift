import CloudKit
import os
import SwiftUI

#if os(iOS)
import UIKit

struct CloudKitSharingView: UIViewControllerRepresentable {
    let group: BudgetGroup

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(
            preparationHandler: { _, completion in
                Task { @MainActor in
                    do {
                        let share = try await CloudKitSharedAreaService.shared.prepareShare(for: group)
                        completion(
                            share,
                            CKContainer(identifier: CloudKitSharedAreaService.containerIdentifier),
                            nil
                        )
                    } catch {
                        completion(nil, nil, error as NSError)
                    }
                }
            }
        )
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(groupName: group.name)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let groupName: String

        init(groupName: String) {
            self.groupName = groupName
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            AppLogger.persistence.error("CloudKit-Bereich konnte nicht geteilt werden: \(error.localizedDescription)")
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            groupName
        }
    }
}
#endif
