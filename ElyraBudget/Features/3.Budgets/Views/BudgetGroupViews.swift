import SwiftData
import SwiftUI
import os

struct BudgetGroupMenu: View {
    @Binding var selection: BudgetGroup?
    let groups: [BudgetGroup]
    let add: () -> Void
    let manage: () -> Void
    let settings: () -> Void

    init(
        selection: Binding<BudgetGroup?>,
        groups: [BudgetGroup],
        add: @escaping () -> Void = {},
        manage: @escaping () -> Void,
        settings: @escaping () -> Void = {}
    ) {
        _selection = selection
        self.groups = groups
        self.add = add
        self.manage = manage
        self.settings = settings
    }

    var body: some View {
        Menu {
            if !groups.isEmpty {
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

            if !groups.isEmpty {
                Divider()
            }
            Button(action: add) {
                Label("Neuen Bereich hinzufügen", systemImage: "plus")
            }
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
        .accessibilityLabel(selection?.name ?? "Bereich auswählen")
    }
}

struct BudgetGroupManagementView: View {
    @Binding var selectedGroup: BudgetGroup?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ProAccessManager.self) private var proAccess

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

    @State private var sharingGroup: BudgetGroup?
    @State private var showingProUpgrade = false
    @State private var groupPendingDeletion: BudgetGroup?
    @State private var saveErrorMessage: String?

    init(selectedGroup: Binding<BudgetGroup?> = .constant(nil)) {
        _selectedGroup = selectedGroup
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Budgetbereiche") {
                    ForEach(groups) { group in
                        HStack(spacing: 12) {
                            IconBadgeView(
                                iconName: group.iconName,
                                color: Color(hexString: group.iconColorHex),
                                size: 34
                            )
                            Text(group.name)
                                .foregroundStyle(.primary)
                            Spacer()

                            Menu {
                                Button {
                                    if proAccess.hasPro {
                                        sharingGroup = group
                                    } else {
                                        showingProUpgrade = true
                                    }
                                } label: {
                                    Label("Bereich teilen", systemImage: "person.2.badge.plus")
                                }

                                Button {
                                    guard groups.count > 1 else { return }
                                    archive(group)
                                } label: {
                                    Label("Archivieren", systemImage: "archivebox")
                                }
                                .disabled(groups.count == 1)

                                Button(role: .destructive) {
                                    groupPendingDeletion = group
                                } label: {
                                    Label("Bereich löschen", systemImage: "trash")
                                }
                                .disabled(groups.count == 1)
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("Optionen für \(group.name)")
                        }
                        .contentShape(Rectangle())
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                guard groups.count > 1 else { return }
                                archive(group)
                            } label: {
                                Label("Archivieren", systemImage: "archivebox")
                            }
                            .tint(.orange)
                            .disabled(groups.count == 1)
                        }
                    }
                    .onMove { source, destination in
                        var reordered = groups
                        reordered.move(fromOffsets: source, toOffset: destination)
                        for (index, group) in reordered.enumerated() {
                            group.sortOrder = index
                            group.updatedAt = .now
                        }
                        do {
                            try modelContext.save()
                        } catch {
                            saveErrorMessage = "Die Reihenfolge konnte nicht gespeichert werden."
                        }
                    }
                    if groups.count == 1 {
                        Text("Der letzte aktive Bereich kann nicht archiviert werden.")
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
                                Button {
                                    groupPendingDeletion = group
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                                .accessibilityLabel("\(group.name) löschen")
                            }
                        }
                    }
                }
            }
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            #endif
            .navigationTitle("Budgetbereiche")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sheet(item: $sharingGroup) { group in
                NavigationStack {
                    CloudKitSharingView(group: group)
                        .ignoresSafeArea()
                        .navigationTitle("Bereich teilen")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                }
            }
            .sheet(isPresented: $showingProUpgrade) {
                ProUpgradeView(feature: "Geteilte Budgetbereiche")
            }
            .alert(
                "Bereich löschen?",
                isPresented: Binding(
                    get: { groupPendingDeletion != nil },
                    set: { if !$0 { groupPendingDeletion = nil } }
                )
            ) {
                Button("Bereich löschen", role: .destructive) {
                    guard let group = groupPendingDeletion else { return }
                    delete(group)
                    groupPendingDeletion = nil
                }
                Button("Abbrechen", role: .cancel) {
                    groupPendingDeletion = nil
                }
            } message: {
                Text("Der Bereich \(groupPendingDeletion?.name ?? "") und alle darin enthaltenen Daten werden dauerhaft gelöscht.")
            }
            .saveErrorAlert(message: $saveErrorMessage)
        }
    }

    private func archive(_ group: BudgetGroup) {
        guard groups.count > 1 else {
            saveErrorMessage = "Mindestens ein Budgetbereich muss aktiv bleiben."
            return
        }

        group.isArchived = true
        group.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = "Der Budgetbereich konnte nicht archiviert werden."
        }
    }

    private func delete(_ group: BudgetGroup) {
        guard !groups.isEmpty else {
            saveErrorMessage = "Mindestens ein Budgetbereich muss aktiv bleiben."
            return
        }

        let groupID = group.id
        var deletedRecords: [(String, SharedBudgetAreaRecordKind)] = []
        deletedRecords += (group.monthlyAllocations ?? []).map {
            (CloudKitSharedAreaService.allocationKey(for: $0.monthStart), .allocation)
        }
        deletedRecords += (group.budgets ?? []).map { ($0.id.uuidString, .budget) }
        deletedRecords += (group.fixedCosts ?? []).map { ($0.id.uuidString, .fixedCost) }
        deletedRecords += (group.savingsGoals ?? []).flatMap { goal in
            [(goal.id.uuidString, SharedBudgetAreaRecordKind.savingsGoal)]
                + (goal.contributions ?? []).map { ($0.id.uuidString, .contribution) }
        }
        deletedRecords += (group.transactions ?? []).map { ($0.id.uuidString, .transaction) }

        for allocation in group.monthlyAllocations ?? [] {
            modelContext.delete(allocation)
        }
        for contribution in (group.savingsGoals ?? []).flatMap({ $0.contributions ?? [] }) {
            modelContext.delete(contribution)
        }
        for budget in group.budgets ?? [] {
            modelContext.delete(budget)
        }
        for fixedCost in group.fixedCosts ?? [] {
            modelContext.delete(fixedCost)
        }
        for savingsGoal in group.savingsGoals ?? [] {
            modelContext.delete(savingsGoal)
        }
        for transaction in group.transactions ?? [] {
            modelContext.delete(transaction)
        }

        if selectedGroup?.id == group.id {
            selectedGroup = nil
        }
        modelContext.delete(group)

        do {
            try modelContext.save()
            for (key, kind) in deletedRecords {
                CloudKitSharedAreaService.recordDeletion(key: key, kind: kind, groupID: groupID)
            }
            if CloudKitSharedAreaService.isShared(groupID: groupID) {
                CloudKitSharedAreaService.suppressSharedArea(groupID: groupID)
                Task {
                    do {
                        try await CloudKitSharedAreaService.deleteSharedArea(groupID: groupID)
                    } catch {
                        AppLogger.persistence.error(
                            "Geteilter Budgetbereich konnte nicht aus CloudKit gelöscht werden: \(error.localizedDescription)"
                        )
                    }
                }
            }
        } catch {
            saveErrorMessage = "Der Bereich konnte nicht gelöscht werden."
        }
    }

    private func restore(_ group: BudgetGroup) {
        group.isArchived = false
        group.updatedAt = .now
        group.sortOrder = groups.count
        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = "Der Budgetbereich konnte nicht wiederhergestellt werden."
        }
    }
}

struct BudgetGroupEditorView: View {
    let group: BudgetGroup?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCurrencyCode) private var currencyCode
    @Query private var transactions: [Transaction]
    @Query private var savingsGoals: [SavingsGoal]
    @Query private var savingsContributions: [SavingsContribution]
    @State private var name: String
    @State private var selectedIcon: String
    @State private var selectedColorHex: String
    @State private var standardMonthlyBudget: Decimal?
    @State private var greenBudgetThreshold: Int
    @State private var orangeBudgetThreshold: Int
    private let selectedMonth: Date
    @State private var hasMonthlyOverride: Bool
    @State private var monthlyOverride: Decimal?
    @State private var showingIconPicker = false
    @State private var roundUpTransactionsEnabled: Bool
    @State private var showingRoundUpConfirmation = false
    @State private var saveErrorMessage: String?

    private let iconColumns = Array(
        repeating: GridItem(.flexible(), spacing: 12),
        count: 5
    )

    private let featuredIcons = CategoryIconLibrary.budgetFeatured

    init(group: BudgetGroup?, selectedDate: Date = .now) {
        self.group = group
        _name = State(initialValue: group?.name ?? "")
        _selectedIcon = State(initialValue: group?.iconName ?? "person.2.fill")
        _selectedColorHex = State(initialValue: group?.iconColorHex ?? ColorPreset.blue.hex)
        _standardMonthlyBudget = State(initialValue: group.flatMap { $0.standardMonthlyBudget > 0 ? $0.standardMonthlyBudget : nil })
        _greenBudgetThreshold = State(initialValue: group?.greenBudgetThreshold ?? 70)
        _orangeBudgetThreshold = State(initialValue: group?.orangeBudgetThreshold ?? 100)
        let month = Calendar.current.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
        self.selectedMonth = month
        _hasMonthlyOverride = State(initialValue: group?.monthlyAllocation(for: month) != nil)
        _monthlyOverride = State(initialValue: group?.monthlyAllocation(for: month)?.amount)
        _roundUpTransactionsEnabled = State(initialValue: group?.roundUpTransactionsEnabled ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Budgetbereich") {
                    TextField("Bezeichnung", text: $name)
                }

                Section {
                    HStack {
                        Text("Jeden Monat automatisch")
                        Spacer()
                        TextField("Kein Kontingent", value: $standardMonthlyBudget, format: .number.precision(.fractionLength(0 ... 2)))
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 130)
                        Text(currencySymbol)
                            .foregroundStyle(.secondary)
                    }

                } header: {
                    Text("Standardbudget")
                } footer: {
                    Text("Dieses Budget gilt automatisch für Monate ohne eigene Anpassung.")
                }

                Section {
                    HStack {
                        Text("Individueller Betrag für \(monthTitle)")
                        Spacer()
                        TextField(
                            "Standard",
                            value: monthlyOverrideBinding,
                            format: .number.precision(.fractionLength(0 ... 2))
                        )
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 130)
                        Text(currencySymbol)
                            .foregroundStyle(.secondary)
                    }

                    if hasMonthlyOverride {
                        Button("Standardbudget verwenden") {
                            hasMonthlyOverride = false
                            monthlyOverride = nil
                        }
                    } else {
                        Text("Aktuell wird das Standardbudget verwendet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Budget diesen Monat")
                } footer: {
                    Text("Dieser Betrag gilt nur für \(monthTitle). In allen anderen Monaten wird das Standardbudget verwendet.")
                }

                budgetStatusSection

                Section("Automatisches Sparen") {
                    Toggle("Buchungen aufrunden", isOn: Binding(
                        get: { roundUpTransactionsEnabled },
                        set: { newValue in
                            if newValue {
                                showingRoundUpConfirmation = true
                            } else {
                                roundUpTransactionsEnabled = false
                            }
                        }
                    ))

                    Text("Ausgaben werden auf den nächsten vollen Euro aufgerundet. Die Differenz wird automatisch als freie Rücklage gespeichert.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
            .alert("Buchungen automatisch aufrunden?", isPresented: $showingRoundUpConfirmation) {
                Button("Aufrundung aktivieren") {
                    roundUpTransactionsEnabled = true
                }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Wenn du diese Funktion aktivierst, werden die Ausgaben in diesem Bereich auf den nächsten vollen Euro aufgerundet. Die jeweilige Differenz wird automatisch in einer neuen freien Rücklage gesammelt.")
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

    private var budgetStatusSection: some View {
        Section {
            Stepper {
                LabeledContent("Grün bis") {
                    Text("\(greenBudgetThreshold) %")
                        .foregroundStyle(.green)
                }
            } onIncrement: {
                greenBudgetThreshold = min(greenBudgetThreshold + 1, orangeBudgetThreshold - 1)
            } onDecrement: {
                greenBudgetThreshold = max(greenBudgetThreshold - 1, 1)
            }

            Stepper {
                LabeledContent("Orange bis") {
                    Text("\(orangeBudgetThreshold) %")
                        .foregroundStyle(.orange)
                }
            } onIncrement: {
                orangeBudgetThreshold += 1
            } onDecrement: {
                orangeBudgetThreshold = max(orangeBudgetThreshold - 1, greenBudgetThreshold + 1)
            }

            LabeledContent("Rot ab") {
                Text("\(orangeBudgetThreshold + 1) %")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Budgetstatus")
        } footer: {
            Text("Die Farben der Budgetkarte zeigen, wie viel dieses Bereichs bereits verwendet wurde.")
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
        value.greenBudgetThreshold = greenBudgetThreshold
        value.orangeBudgetThreshold = orangeBudgetThreshold
        if group == nil {
            value.sortOrder = 0
            modelContext.insert(value)
        }

        let monthStart = Calendar.current.dateInterval(of: .month, for: selectedMonth)?.start ?? selectedMonth
        var deletedMonthlyAllocationKey: String?
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
            deletedMonthlyAllocationKey = CloudKitSharedAreaService.allocationKey(for: existing.monthStart)
            modelContext.delete(existing)
        }

        if roundUpTransactionsEnabled {
            do {
                try TransactionRoundUpService.enable(
                    for: value,
                    transactions: transactions,
                    savingsGoals: savingsGoals,
                    contributions: savingsContributions,
                    modelContext: modelContext
                )
            } catch {
                saveErrorMessage = "Die Aufrundung konnte nicht aktiviert werden."
                return
            }
        }

        do {
            try modelContext.save()
            if let deletedMonthlyAllocationKey {
                CloudKitSharedAreaService.recordDeletion(
                    key: deletedMonthlyAllocationKey,
                    kind: .allocation,
                    groupID: value.id
                )
            }
            dismiss()
        } catch {
            saveErrorMessage = "Der Budgetbereich konnte nicht gespeichert werden."
        }
    }

    private var selectedColor: Color {
        Color(hexString: selectedColorHex)
    }

    private var monthTitle: String {
        selectedMonth.formatted(.dateTime.month(.wide).year())
    }

    private var monthlyOverrideBinding: Binding<Decimal> {
        Binding(
            get: {
                monthlyOverride ?? standardMonthlyBudget ?? .zero
            },
            set: { newValue in
                monthlyOverride = newValue
                hasMonthlyOverride = true
            }
        )
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
