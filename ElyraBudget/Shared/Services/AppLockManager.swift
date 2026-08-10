import Foundation
import LocalAuthentication
import Observation
import SwiftUI

@Observable
@MainActor
final class AppLockManager {
    var isLocked = false
    private(set) var isAuthenticating = false
    var authenticationError: String?

    func lockIfNeeded(isEnabled: Bool, hasPro: Bool) {
        guard isEnabled, hasPro else {
            isLocked = false
            authenticationError = nil
            return
        }
        isLocked = true
        authenticationError = nil
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        authenticationError = nil
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = "Abbrechen"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authenticationError = "Auf diesem Gerät ist keine Gerätesperre eingerichtet."
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Entsperre Elyra Budget, um deine Finanzdaten zu sehen."
            )
            if success { isLocked = false }
        } catch {
            authenticationError = "Die App konnte nicht entsperrt werden."
        }
    }
}

struct AppLockView: View {
    @Environment(AppLockManager.self) private var appLock

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.tint)

            Text("Elyra Budget ist gesperrt")
                .font(.title2.bold())

            Text("Deine Finanzdaten bleiben geschützt.")
                .foregroundStyle(.secondary)

            Button {
                Task { await appLock.unlock() }
            } label: {
                Label(
                    appLock.isAuthenticating ? "Prüfe Identität …" : "Mit Face ID oder Touch ID entsperren",
                    systemImage: "faceid"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(appLock.isAuthenticating)

            if let authenticationError = appLock.authenticationError {
                Text(authenticationError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .task { await appLock.unlock() }
    }
}
