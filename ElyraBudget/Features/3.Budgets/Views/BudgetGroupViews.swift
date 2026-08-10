import SwiftData
import SwiftUI

struct BudgetGroupMenu: View {
    @Binding var selection: BudgetGroup?
    let groups: [BudgetGroup]
    let manage: () -> Void
    let settings: () -> Void

    init(
        selection: Binding<BudgetGroup?>,
        groups: [BudgetGroup],
        manage: @escaping () -> Void,
        settings: @escaping () -> Void = {}
    ) {
        _selection = selection
        self.groups = groups
        self.manage = manage
        self.settings = settings
    }

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

            Button(action: settings) {
                Label("Einstellungen", systemImage: "gearshape")
            }
        } label: {
            Image(systemName: selection?.iconName ?? "person.2.fill")
                .foregroundStyle(
                    selection.map { Color(hexString: $0.iconColorHex) } ?? .secondary
                )
        }
        .accessibilityLabel(selection?.name ?? "Budgetbereich auswählen")
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

    @Query(
        filter: #Predicate<BudgetGroup> { $0.isArchived },
        sort: [SortDescriptor<BudgetGroup>(\.updatedAt, order: .reverse)]
    ) private var archivedGroups: [BudgetGroup]

    @State private var editingGroup: BudgetGroup?
    @State private var showingNewEditor = false

    var body: some View {
        NavigationStack {
            List {
                Section("Budgetbereiche") {
                    ForEach(groups) { group in
                        HStack(spacing: 12) {
                            Button {
                                editingGroup = group
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
                            .buttonStyle(.plain)

                            Menu {
                                Button {
                                    archive(group)
                                } label: {
                                    Label("Archivieren", systemImage: "archivebox")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("Optionen für \(group.name)")
                        }
                        .contentShape(Rectangle())
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                archive(group)
                            } label: {
                                Label("Archivieren", systemImage: "archivebox")
                            }
                            .tint(.orange)
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
                        showingNewEditor = true
                    } label: {
                        Label("Neuen Bereich hinzufügen", systemImage: "plus")
                    }
                }

                if !archivedGroups.isEmpty {
                    Section("Archivierte Bereiche") {
                        ForEach(archivedGroups) { group in
                            HStack(spacing: 12) {
                                IconBadgeView(
                                    iconName: group.iconName,
                                    color: Color(hexString: group.iconColorHex),
                                    size: 34
                                )
                                Text(group.name)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Wiederherstellen") {
                                    restore(group)
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.tint)
                            }
                        }
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
            .sheet(item: $editingGroup) { group in
                BudgetGroupEditorView(group: group)
            }
            .sheet(isPresented: $showingNewEditor) {
                BudgetGroupEditorView(group: nil)
            }
        }
    }

    private func archive(_ group: BudgetGroup) {
        group.isArchived = true
        group.updatedAt = .now
        try? modelContext.save()
    }

    private func restore(_ group: BudgetGroup) {
        group.isArchived = false
        group.updatedAt = .now
        group.sortOrder = groups.count
        try? modelContext.save()
    }
}

private struct BudgetGroupEditorView: View {
    let group: BudgetGroup?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCurrencyCode) private var currencyCode
    @State private var name: String
    @State private var selectedIcon: String
    @State private var selectedColorHex: String
    @State private var standardMonthlyBudget: Decimal?
    @State private var selectedMonth: Date
    @State private var hasMonthlyOverride: Bool
    @State private var monthlyOverride: Decimal?
    @State private var showingIconPicker = false
    @State private var saveErrorMessage: String?

    private let iconColumns = Array(
        repeating: GridItem(.flexible(), spacing: 12),
        count: 5
    )

    private let featuredIcons = CategoryIconLibrary.budgetFeatured

    init(group: BudgetGroup?) {
        self.group = group
        _name = State(initialValue: group?.name ?? "")
        _selectedIcon = State(initialValue: group?.iconName ?? "person.2.fill")
        _selectedColorHex = State(initialValue: group?.iconColorHex ?? ColorPreset.blue.hex)
        _standardMonthlyBudget = State(initialValue: group.flatMap { $0.standardMonthlyBudget > 0 ? $0.standardMonthlyBudget : nil })
        let month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        _selectedMonth = State(initialValue: month)
        _hasMonthlyOverride = State(initialValue: group?.monthlyAllocation(for: month) != nil)
        _monthlyOverride = State(initialValue: group?.monthlyAllocation(for: month)?.amount)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Budgetbereich") {
                    TextField("Bezeichnung", text: $name)
                }

                Section {
                    HStack {
                        Text("Standard pro Monat")
                        Spacer()
                        TextField("Kein Kontingent", value: $standardMonthlyBudget, format: .number.precision(.fractionLength(0 ... 2)))
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 130)
                        Text(currencySymbol)
                            .foregroundStyle(.secondary)
                    }

                    DatePicker("Monat", selection: $selectedMonth, displayedComponents: [.date])
                        .datePickerStyle(.compact)

                    Toggle("Individuellen Monatswert verwenden", isOn: $hasMonthlyOverride)

                    if hasMonthlyOverride {
                        HStack {
                            Text("Kontingent für diesen Monat")
                            Spacer()
                            TextField("Betrag", value: $monthlyOverride, format: .number.precision(.fractionLength(0 ... 2)))
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 130)
                            Text(currencySymbol)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Monatliches Kontingent")
                } footer: {
                    Text("Nicht angepasste Monate verwenden automatisch den Standardwert.")
                }

                Section("Darstellung") {
                    Text("Icon")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: iconColumns, spacing: 12) {
                        ForEach(featuredIcons, id: \.self) { iconName in
                            iconButton(iconName)
                        }
                    }

                    Button {
                        showingIconPicker = true
                    } label: {
                        Label("Weitere Icons", systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PresetColorSelectionView(selection: $selectedColorHex)
                }
            }
            .navigationTitle(group == nil ? "Neuer Bereich" : "Bereich bearbeiten")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .sheet(isPresented: $showingIconPicker) {
                IconPickerView(selectedIcon: $selectedIcon)
            }
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
        value.iconName = selectedIcon
        value.iconColorHex = selectedColorHex
        value.updatedAt = .now
        value.standardMonthlyBudget = normalizedStandardMonthlyBudget
        if group == nil {
            value.sortOrder = 0
            modelContext.insert(value)
        }

        let monthStart = Calendar.current.dateInterval(of: .month, for: selectedMonth)?.start ?? selectedMonth
        if hasMonthlyOverride {
            if let existing = value.monthlyAllocation(for: monthStart) {
                existing.amount = normalizedMonthlyOverride
                existing.updatedAt = .now
            } else {
                let allocation = BudgetGroupMonthlyAllocation(
                    monthStart: monthStart,
                    amount: normalizedMonthlyOverride,
                    group: value
                )
                modelContext.insert(allocation)
            }
        } else if let existing = value.monthlyAllocation(for: monthStart) {
            modelContext.delete(existing)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveErrorMessage = "Der Budgetbereich konnte nicht gespeichert werden."
        }
    }

    private var selectedColor: Color {
        Color(hexString: selectedColorHex)
    }

    private var currencySymbol: String {
        AppCurrency(rawValue: currencyCode)?.symbol ?? currencyCode
    }

    private var normalizedStandardMonthlyBudget: Decimal {
        guard let standardMonthlyBudget, standardMonthlyBudget > 0 else { return 0 }
        return standardMonthlyBudget
    }

    private var normalizedMonthlyOverride: Decimal {
        guard let monthlyOverride, monthlyOverride >= 0 else { return 0 }
        return monthlyOverride
    }

    private func iconButton(_ iconName: String) -> some View {
        let isSelected = selectedIcon == iconName

        return Button {
            selectedIcon = iconName
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? selectedColor.opacity(0.18) : Color.secondary.opacity(0.08))
                    .frame(width: 48, height: 48)
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? selectedColor : .secondary)
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(selectedColor, lineWidth: 2)
                        .frame(width: 48, height: 48)
                }
            }
        }
        .buttonStyle(.plain)
    }

}
