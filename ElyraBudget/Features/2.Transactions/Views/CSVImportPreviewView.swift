import SwiftUI

struct CSVImportPreviewView: View {
    let rows: [CSVImportRow]
    let onImport: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(rows.count) Buchungen werden importiert. Bestehende Buchungen bleiben unverändert.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Vorschau") {
                    ForEach(rows.prefix(50)) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.title).font(.headline)
                                Text(row.date, format: .dateTime.day().month().year())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(row.amount, format: .currency(code: "EUR"))
                        }
                    }
                }
            }
            .navigationTitle("CSV importieren")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importieren", action: onImport)
                }
            }
        }
    }
}
