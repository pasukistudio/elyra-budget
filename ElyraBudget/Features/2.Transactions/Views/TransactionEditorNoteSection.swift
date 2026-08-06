import SwiftUI

struct TransactionEditorNoteSection: View {
    @Binding var note: String
    let cardBackground: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TransactionEditorSectionHeader(title: "Notiz")

            TextField("Optional", text: $note, axis: .vertical)
                .lineLimit(4 ... 8)
                .padding(.horizontal, 17)
                .padding(.vertical, 15)
                .frame(minHeight: 125, alignment: .topLeading)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
        }
    }
}
