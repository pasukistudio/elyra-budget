import SwiftUI

struct NotificationSettingsView: View {
    let profile: UserSettings?
    let saveSettings: () -> Void
    let requestPermission: (Bool) -> Void

    var body: some View {
        Form {
            NotificationSettingsSection(
                profile: profile,
                saveSettings: saveSettings,
                requestPermission: requestPermission
            )
        }
        .navigationTitle("Benachrichtigungen")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
