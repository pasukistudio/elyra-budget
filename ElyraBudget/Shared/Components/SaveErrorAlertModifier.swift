import SwiftUI

struct SaveErrorAlertModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert(
            "Speichern fehlgeschlagen",
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                message = nil
            }
        } message: {
            Text(message ?? "Die Änderung konnte nicht gespeichert werden.")
        }
    }
}

extension View {
    func saveErrorAlert(message: Binding<String?>) -> some View {
        modifier(SaveErrorAlertModifier(message: message))
    }
}
