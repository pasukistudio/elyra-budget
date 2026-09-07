import CoreData
import CloudKit
import Foundation
import Observation
import SwiftUI

enum AppRuntimeConfiguration {
    static func isRunningUnderXCTest(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        arguments.contains("-XCTest")
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    static func isCloudKitEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        if let override = environment["ELYRA_BUDGET_USE_CLOUDKIT"] {
            return override != "NO"
        }

        return !isRunningUnderXCTest(environment: environment, arguments: arguments)
    }
}

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

extension Notification.Name {
    static let elyraSharedSyncStarted = Notification.Name("ElyraBudget.sharedSyncStarted")
    static let elyraSharedSyncSucceeded = Notification.Name("ElyraBudget.sharedSyncSucceeded")
    static let elyraSharedSyncFailed = Notification.Name("ElyraBudget.sharedSyncFailed")
}

@Observable
final class CloudKitSyncMonitor {
    private(set) var status: CloudKitSyncStatus
    private(set) var lastSyncDate: Date?
    private(set) var lastImportDate: Date?
    private(set) var errorMessage: String?
    private(set) var sharedStatus: CloudKitSyncStatus = .idle
    private(set) var sharedLastSyncDate: Date?
    private(set) var sharedErrorMessage: String?

    let isCloudKitEnabled: Bool
    private var observerTokens: [NSObjectProtocol] = []

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        isCloudKitEnabled = AppRuntimeConfiguration.isCloudKitEnabled(
            environment: environment
        )
        status = isCloudKitEnabled ? .idle : .unavailable
        lastImportDate = nil

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
            center.addObserver(forName: .elyraSharedSyncStarted, object: nil, queue: .main) { [weak self] _ in
                self?.sharedStatus = .syncing
                self?.sharedErrorMessage = nil
            }
        )
        observerTokens.append(
            center.addObserver(forName: .elyraSharedSyncSucceeded, object: nil, queue: .main) { [weak self] _ in
                self?.sharedStatus = .succeeded
                self?.sharedLastSyncDate = .now
                self?.sharedErrorMessage = nil
            }
        )
        observerTokens.append(
            center.addObserver(forName: .elyraSharedSyncFailed, object: nil, queue: .main) { [weak self] notification in
                self?.sharedStatus = .failed
                self?.sharedErrorMessage = notification.userInfo?["message"] as? String
                    ?? "Geteilter Bereich konnte nicht synchronisiert werden."
            }
        )
    }

    deinit {
        let center = NotificationCenter.default
        observerTokens.forEach(center.removeObserver)
    }

    func handle(event: NSPersistentCloudKitContainer.Event) {
        if event.type == .import, event.endDate != nil, event.succeeded {
            lastImportDate = event.endDate
        }
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
            errorMessage = Self.detailedErrorDescription(error)
        }
    }

    private static func detailedErrorDescription(_ error: Error?) -> String {
        guard let error else { return "Unbekannter iCloud-Fehler." }

        guard let cloudKitError = error as? CKError else {
            return error.localizedDescription
        }

        var details = "CKError \(cloudKitError.code.rawValue): \(cloudKitError.localizedDescription)"

        if let underlyingError = cloudKitError.userInfo[NSUnderlyingErrorKey] as? Error {
            details += " Ursache: \(underlyingError.localizedDescription)"
        }

        let additionalInfo = cloudKitError.userInfo
            .filter { key, _ in key != NSUnderlyingErrorKey }
            .map { "($0.key)=\($0.value)" }
            .joined(separator: ", ")
        if !additionalInfo.isEmpty {
            details += " Details: \(additionalInfo)"
        }

        return details
    }

    func clearError() {
        guard status == .failed else { return }
        status = .idle
        errorMessage = nil
    }

    func clearSharedError() {
        guard sharedStatus == .failed else { return }
        sharedStatus = .idle
        sharedErrorMessage = nil
    }

    @MainActor
    func waitForInitialImport() async -> Bool {
        guard isCloudKitEnabled else { return false }
        guard lastImportDate == nil else { return true }

        return await withTaskGroup(of: Bool?.self) { group in
            group.addTask { @MainActor in
                for await notification in NotificationCenter.default.notifications(
                    named: NSPersistentCloudKitContainer.eventChangedNotification
                ) {
                    guard let event = notification.userInfo?[
                        NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                    ] as? NSPersistentCloudKitContainer.Event,
                    event.type == .import,
                    event.endDate != nil else { continue }

                    return event.succeeded
                }
                return nil
            }

            group.addTask {
                try? await Task.sleep(for: .seconds(10))
                return nil
            }

            let result = await group.next() ?? nil
            group.cancelAll()
            return result ?? false
        }
    }
}

struct CloudKitSyncStatusView: View {
    let monitor: CloudKitSyncMonitor

    var body: some View {
        let displayedStatus = monitor.sharedStatus == .failed ? .failed
            : (monitor.status == .failed ? .failed : monitor.status)
        Menu {
            Label(displayedStatus.title, systemImage: displayedStatus.systemImage)

            if monitor.sharedStatus != .idle {
                Divider()
                Label("Geteilte Bereiche: \(monitor.sharedStatus.title)", systemImage: monitor.sharedStatus.systemImage)
            }

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
            if let sharedErrorMessage = monitor.sharedErrorMessage {
                Divider()
                Text(sharedErrorMessage)
                    .foregroundStyle(.secondary)
                Button("Fehler ausblenden") {
                    monitor.clearSharedError()
                }
            }
        } label: {
            Image(systemName: displayedStatus.systemImage)
                .symbolEffect(.pulse, isActive: displayedStatus == .syncing)
        }
        .tint(displayedStatus == .failed ? .red : nil)
        .accessibilityLabel(displayedStatus.title)
    }
}
