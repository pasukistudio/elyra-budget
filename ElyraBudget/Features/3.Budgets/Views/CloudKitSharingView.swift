import CloudKit
import os
import SwiftUI

#if os(iOS)
import UIKit

struct CloudKitSharingView: View {
    let group: BudgetGroup

    @State private var share: CKShare?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let share {
                CloudKitShareController(share: share, title: group.name)
            } else {
                ProgressView("Freigabe wird vorbereitet …")
            }
        }
        .task {
            do {
                share = try await CloudKitSharedAreaService.shared.prepareShare(for: group)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert("Bereich konnte nicht geteilt werden", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unbekannter Fehler")
        }
    }
}

private struct CloudKitShareController: UIViewControllerRepresentable {
    let share: CKShare
    let title: String

    func makeCoordinator() -> Coordinator {
        Coordinator(title: title)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(
            share: share,
            container: CKContainer(identifier: CloudKitSharedAreaService.containerIdentifier)
        )
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let title: String

        init(title: String) {
            self.title = title
        }

        private let logger = Logger(
            subsystem: "de.pasukistudio.elyrabudget",
            category: "CloudKit"
        )

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            logger.error("CloudKit share could not be saved: \(error.localizedDescription, privacy: .public)")
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            title
        }
    }
}
#endif

#if os(macOS)
struct CloudKitSharingView: View {
    let group: BudgetGroup

    @State private var shareURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 42))
                .foregroundStyle(Color.accentColor)
            Text("Bereich teilen")
                .font(.title2.bold())
            Text("Bereite einen CloudKit-Link für „\(group.name)“ vor.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if let shareURL {
                ShareLink(item: shareURL) {
                    Label("Einladungslink teilen", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Freigabe vorbereiten") {
                    Task {
                        do {
                            let share = try await CloudKitSharedAreaService.shared.prepareShare(for: group)
                            shareURL = share.url
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(minWidth: 340, minHeight: 240)
        .alert("Bereich konnte nicht geteilt werden", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unbekannter Fehler")
        }
    }
}
#endif
