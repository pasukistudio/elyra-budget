import CloudKit
import os
import SwiftUI

#if os(iOS)
import UIKit

struct CloudKitSharingView: UIViewControllerRepresentable {
    let group: BudgetGroup

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let itemProvider = NSItemProvider()
        itemProvider.registerCKShare(
            container: CKContainer(identifier: CloudKitSharedAreaService.containerIdentifier),
            allowedSharingOptions: .standard
        ) { @MainActor in
            try await CloudKitSharedAreaService.shared.prepareShare(for: group)
        }

        let configuration = UIActivityItemsConfiguration(itemProviders: [itemProvider])
        configuration.metadataProvider = { key in
            key == .title ? group.name : nil
        }

        return UIActivityViewController(activityItemsConfiguration: configuration)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
