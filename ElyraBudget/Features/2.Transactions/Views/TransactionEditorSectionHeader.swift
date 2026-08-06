import SwiftUI

struct TransactionEditorSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }
}
