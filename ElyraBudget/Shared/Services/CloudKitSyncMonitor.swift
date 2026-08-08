import CoreData
import Foundation
import Observation
import SwiftUI

enum CloudKitSyncStatus: Equatable {
    case unavailable
    case idle
    case syncing
    case succeeded
    case failed

    var title: String {
        switch self {
        case .unavailable: return "iCloud-Synchronisierung nicht aktiv"
        case .idle: return "iCloud-Synchronisierung bereit"
        case .syncing: return "iCloud-Synchronisierung läuft"
        case .succeeded: return "iCloud-Synchronisierung abgeschlossen"
        case .failed: return "iCloud-Synchronisierung fehlgeschlagen"
        }
    }

    var systemImage: String {
        switch self {
        case .unavailable: return "icloud.slash"
        case .idle: return "icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .succeeded: return "checkmark.icloud"
        case .failed: return "exclamationmark.icloud"
        }
    }
}

@Observable
final class CloudKitSyncMonitor {
    private(set) var status: CloudKitSyncStatus
    private(set) var lastSyncDate: Date?
    private(set) var errorMessage: String?

    let isCloudKitEnabled: Bool
    private var observerTokens: [NSObjectProtocol] = []

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let isRunningUnderXCTest = environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
        isCloudKitEnabled = !isRunningUnderXCTest
            && environment["ELYRA_BUDGET_USE_CLOUDKIT"] != "NO"
        status = isCloudKitEnabled ? .idle : .unavailable

        guard isCloudKitEnabled else { return }
        let center = NotificationCenter.default
        observerTokens.append(
            center.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let event = notification.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event else { return }
                self?.handle(event: event)
            }
        )
        observerTokens.append(
            center.addObserver(
                forName: .NSPersistentStoreRemoteChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, self.isCloudKitEnabled else { return }
                self.status = .syncing
                self.errorMessage = nil
            }
        )
    }

    deinit {
        let center = NotificationCenter.default
        observerTokens.forEach(center.removeObserver)
    }

    func handle(event: NSPersistentCloudKitContainer.Event) {
        handle(
            type: event.type,
            isFinished: event.endDate != nil,
            succeeded: event.succeeded,
            error: event.error
        )
    }

    func handle(
        type: NSPersistentCloudKitContainer.EventType,
        isFinished: Bool,
        succeeded: Bool,
        error: Error?
    ) {
        guard isCloudKitEnabled else { return }

        if !isFinished {
            status = .syncing
            errorMessage = nil
            return
        }

        if succeeded {
            status = .succeeded
            lastSyncDate = .now
            errorMessage = nil
        } else {
            status = .failed
            errorMessage = error?.localizedDescription ?? "Unbekannter iCloud-Fehler."
        }
    }

    func clearError() {
        guard status == .failed else { return }
        status = .idle
        errorMessage = nil
    }
}

struct CloudKitSyncStatusView: View {
    let monitor: CloudKitSyncMonitor

    var body: some View {
        Menu {
            Label(monitor.status.title, systemImage: monitor.status.systemImage)

            if let lastSyncDate = monitor.lastSyncDate {
                Text("Zuletzt aktualisiert: \(lastSyncDate.formatted(date: .abbreviated, time: .shortened))")
            }

            if let errorMessage = monitor.errorMessage {
                Divider()
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Fehler ausblenden") {
                    monitor.clearError()
                }
            }
        } label: {
            Image(systemName: monitor.status.systemImage)
                .symbolEffect(.pulse, isActive: monitor.status == .syncing)
        }
        .tint(monitor.status == .failed ? .red : nil)
        .accessibilityLabel(monitor.status.title)
    }
}
