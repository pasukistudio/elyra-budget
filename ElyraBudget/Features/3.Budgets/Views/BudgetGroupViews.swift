import SwiftData
import SwiftUI

struct BudgetGroupMenu: View {
    @Binding var selection: BudgetGroup?
    let groups: [BudgetGroup]
    let manage: () -> Void

    var body: some View {
        Menu {
            Button {
                selection = nil
            } label: {
                Label("Alle Bereiche", systemImage: selection == nil ? "checkmark" : "square.dashed")
            }

            if !groups.isEmpty {
                Divider()
                ForEach(groups) { group in
                    Button {
                        selection = group
                    } label: {
                        Label {
                            Text(group.name)
                        } icon: {
                            Image(systemName: group.iconName)
                        }
                    }
                }
            }

            Divider()
            Button(action: manage) {
                Label("Bereiche verwalten", systemImage: "slider.horizontal.3")
            }
        } label: {
            Label(selection?.name ?? "Alle Bereiche", systemImage: "person.2.fill")
                .labelStyle(.titleAndIcon)
        }
        .accessibilityLabel("Budgetbereich auswählen")
    }
}

struct BudgetGroupManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<BudgetGroup> { !$0.isArchived },
        sort: [
            SortDescriptor<BudgetGroup>(\.sortOrder),
            SortDescriptor<BudgetGroup>(\.createdAt)
        ]
    ) private var groups: [BudgetGroup]

    @State private var editingGroup: BudgetGroup?
    @State private var showingEditor = false

    var body: some View {
        NavigationStack {
            List {
                Section("Budgetbereiche") {
                    ForEach(groups) { group in
                        Button {
                            editingGroup = group
                            showingEditor = true
                        } label: {
                            HStack(spacing: 12) {
                                IconBadgeView(
                                    iconName: group.iconName,
                                    color: Color(hexString: group.iconColorHex),
                                    size: 34
                                )
                                Text(group.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onMove { source, destination in
                        var reordered = groups
                        reordered.move(fromOffsets: source, toOffset: destination)
                        for (index, group) in reordered.enumerated() {
                            group.sortOrder = index
                            group.updatedAt = .now
                        }
                        try? modelContext.save()
                    }
                }

                Section {
                    Button {
                        editingGroup = nil
                        showingEditor = true
                    } label: {
                        Label("Neuen Bereich hinzufügen", systemImage: "plus")
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Budgetbereiche")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sheet(isPresented: $showingEditor) {
                BudgetGroupEditorView(group: editingGroup)
            }
        }
    }
}

private struct BudgetGroupEditorView: View {
    let group: BudgetGroup?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name: String
    @State private var saveErrorMessage: String?

    init(group: BudgetGroup?) {
        self.group = group
        _name = State(initialValue: group?.name ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Budgetbereich") {
                    TextField("Bezeichnung", text: $name)
                }
            }
            .navigationTitle(group == nil ? "Neuer Bereich" : "Bereich bearbeiten")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .saveErrorAlert(message: $saveErrorMessage)
        }
    }

    private func save() {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return }

        let value = group ?? BudgetGroup()
        value.name = cleanedName
        value.updatedAt = .now
        if group == nil {
            value.sortOrder = 0
            modelContext.insert(value)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveErrorMessage = "Der Budgetbereich konnte nicht gespeichert werden."
        }
    }
}
