import SwiftData
import SwiftUI

private func recommendedSavingsContribution(
    for fixedCost: FixedCost,
    calendar: Calendar = .autoupdatingCurrent
) -> Decimal {
    guard let dueDate = fixedCost.nextDueDate(after: .now, calendar: calendar) else {
        return fixedCost.amount
    }

    let startMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
    let dueMonth = calendar.dateInterval(of: .month, for: dueDate)?.start ?? dueDate
    let months = max(
        1,
        calendar.dateComponents([.month], from: startMonth, to: dueMonth).month ?? 1
    )
    var rawRecommendation = fixedCost.amount / Decimal(months)
    var roundedRecommendation = rawRecommendation
    NSDecimalRound(&roundedRecommendation, &rawRecommendation, 2, .plain)
    return roundedRecommendation
}

struct SavingsGoalEditorView: View {
    let goal: SavingsGoal?
    let budgets: [Budget]
    let type: SavingsGoalType
    let group: BudgetGroup?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCurrencyCode) private var currencyCode
    @Environment(ProAccessManager.self) private var proAccess

    @Query(sort: [SortDescriptor<Transaction>(\.date)])
    private var transactions: [Transaction]

    @Query(sort: [SortDescriptor<FixedCost>(\.createdAt)])
    private var fixedCosts: [FixedCost]

    @State private var name: String
    @State private var targetAmount: Decimal?
    @State private var contributionAmount: Decimal?
    @State private var frequency: SavingsFrequency
    @State private var schedule: SavingsSchedule
    @State private var anchorDate: Date
    @State private var automaticBooking: Bool
    @State private var note: String
    @State private var selectedBudget: Budget?
    @State private var selectedFixedCost: FixedCost?
    @State private var selectedIcon: String
    @State private var selectedColorHex: String
    @State private var showingIconPicker = false
    @State private var saveErrorMessage: String?

    private let iconColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)
    private let colorColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
    private let featuredIcons = CategoryIconLibrary.budgetFeatured
    private let availableColors = ColorPreset.allCases

    init(
        goal: SavingsGoal?,
        budgets: [Budget],
        type: SavingsGoalType? = nil,
        group: BudgetGroup? = nil,
        linkedFixedCost: FixedCost? = nil
    ) {
        self.goal = goal
        self.budgets = budgets
        self.type = goal?.type ?? type ?? .goal
        self.group = group ?? goal?.group
        let prefill = linkedFixedCost
        _name = State(initialValue: goal?.name ?? prefill?.title ?? "")
        _targetAmount = State(initialValue: goal?.targetAmount ?? prefill?.amount)
        _contributionAmount = State(
            initialValue: goal?.contributionAmount == 0
                ? prefill.map { recommendedSavingsContribution(for: $0) }
                : goal?.contributionAmount
        )
        _frequency = State(initialValue: goal?.frequency ?? (prefill == nil ? .monthly : .monthly))
        _schedule = State(initialValue: goal?.schedule ?? .fixedDay)
        _anchorDate = State(initialValue: goal?.anchorDate ?? .now)
        _automaticBooking = State(initialValue: goal?.automaticBooking ?? (prefill != nil))
        _note = State(initialValue: goal?.note ?? "")
        _selectedBudget = State(initialValue: goal?.budget)
        _selectedFixedCost = State(initialValue: goal?.fixedCost ?? linkedFixedCost)
        _selectedIcon = State(initialValue: goal?.iconName ?? "banknote")
        _selectedColorHex = State(initialValue: goal?.iconColorHex ?? "#34C759")
    }

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                goalSection
                appearanceSection
                intervalSection
                fixedCostSection
                assignmentSection
                noteSection
            }
            .navigationTitle(goal == nil ? type.creationTitle : type.editTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingIconPicker) {
                IconPickerView(selectedIcon: $selectedIcon)
            }
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(!canSave)
                }
            }
            .saveErrorAlert(message: $saveErrorMessage)
        }
    }

    private var previewSection: some View {
        Section("Vorschau") {
            HStack(spacing: 14) {
                IconBadgeView(
                    iconName: selectedIcon,
                    color: selectedColor,
                    size: 48
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Sparzielname" : name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(type == .goal ? (automaticBooking ? "Automatisches Sparen" : "Manuelle Einzahlung") : (automaticBooking ? "Automatische Rücklage" : "Manuelle Rücklage"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(Decimal.zero, format: .currency(code: currencyCode))
                        .font(.headline)
                    if type == .goal, let targetAmount, targetAmount > 0 {
                        Text("von \(targetAmount, format: .currency(code: currencyCode))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var goalSection: some View {
        Section {
            TextField("Bezeichnung", text: $name)
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif

            if type == .goal {
                SavingsAmountRow(title: "Zielbetrag", amount: $targetAmount, currencySymbol: currencySymbol)
            }
        } header: {
            Text(type.title)
        } footer: {
            Text(type == .goal ? "Ein Sparziel benötigt einen Zielbetrag." : "Eine freie Rücklage hat keinen festen Zielbetrag.")
        }
    }

    private var appearanceSection: some View {
        Section("Darstellung") {
            VStack(alignment: .leading, spacing: 12) {
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
                    HStack {
                        Text("Weitere Icons")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .padding(.trailing, 22)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
            .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 12) {
                Text("Icon-Farbe")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: colorColumns, spacing: 10) {
                    ForEach(availableColors) { preset in
                        colorButton(preset)
                    }
                }

                customColorRow
                    .padding(.top, 10)
            }
            .padding(.vertical, 6)
        }
    }

    private func iconButton(_ iconName: String) -> some View {
        let isSelected = selectedIcon == iconName

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedIcon = iconName
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? selectedColor.opacity(0.18) : Color.secondary.opacity(0.08))
                    .frame(width: 48, height: 48)
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? selectedColor : .secondary)
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(selectedColor, lineWidth: 2)
                        .frame(width: 48, height: 48)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Icon auswählen")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func colorButton(_ preset: ColorPreset) -> some View {
        let isSelected = selectedColorHex == preset.hex

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedColorHex = preset.hex
            }
        } label: {
            ZStack {
                Circle()
                    .fill(preset.color)
                    .frame(width: 36, height: 36)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var customColorRow: some View {
        if proAccess.hasPro {
            ColorPicker(selection: customColorBinding, supportsOpacity: false) {
                Text("Eigene Farbe")
            }
            .padding(.trailing, 17)
        } else {
            HStack(spacing: 10) {
                Text("Eigene Farbe")
                    .foregroundStyle(.primary)
                Spacer()
                Text("PRO")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.tint.opacity(0.15), in: Capsule())
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 22)
        }
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { selectedColor },
            set: { if let hex = $0.toHex() { selectedColorHex = hex } }
        )
    }

    private var selectedColor: Color {
        Color(hexString: selectedColorHex)
    }

    private var currencySymbol: String {
        AppCurrency(rawValue: currencyCode)?.symbol ?? currencyCode
    }

    private var intervalSection: some View {
        Section {
            Toggle("Automatisch sparen", isOn: $automaticBooking)
            if automaticBooking {
                SavingsAmountRow(title: "Sparbetrag", amount: $contributionAmount, currencySymbol: currencySymbol)
                Picker("Häufigkeit", selection: $frequency) {
                    ForEach(SavingsFrequency.allCases) { Text($0.title).tag($0) }
                }
                if frequency.months != nil {
                    Picker("Abbuchung", selection: $schedule) {
                        ForEach(SavingsSchedule.allCases) { Text($0.title).tag($0) }
                    }
                }
                DatePicker("Startdatum", selection: $anchorDate, displayedComponents: .date)
            }
        } header: {
            Text("Intervall")
        }
    }

    private var assignmentSection: some View {
        Section {
            Menu {
                Button("Kein Budget") { selectedBudget = nil }
                ForEach(budgets, id: \.persistentModelID) { budget in
                    Button {
                        selectedBudget = budget
                    } label: {
                        Label(budget.name, systemImage: budget.iconName)
                    }
                }
            } label: {
                HStack {
                    Text("Budget")
                    Spacer()
                    selectedBudgetValue
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.secondary.opacity(0.55))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("Zuordnung")
        } footer: {
            Text("Automatische Sparbuchungen werden als Ausgabe vom ausgewählten Budget erfasst.")
        }
    }

    private var fixedCostSection: some View {
        Group {
            if type == .goal {
                Section {
                    Menu {
                        Button("Keine Fixkosten") { selectedFixedCost = nil }
                        ForEach(availableFixedCosts) { fixedCost in
                            Button {
                                selectedFixedCost = fixedCost
                            } label: {
                                Label(fixedCost.title, systemImage: "calendar.badge.clock")
                            }
                        }
                    } label: {
                        HStack {
                            Text("Fixkosten")
                            Spacer()
                            Text(selectedFixedCost?.title ?? "Keine Fixkosten")
                                .foregroundStyle(selectedFixedCost == nil ? Color.accentColor : Color.secondary)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.secondary.opacity(0.55))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Ziel")
                } footer: {
                    Text("Eine verknüpfte Fixkostenposition bestimmt, wofür das Sparziel aufgebaut wird.")
                }
            }
        }
    }

    private var availableFixedCosts: [FixedCost] {
        fixedCosts.filter { fixedCost in
            guard fixedCost.group === group || (group == nil && fixedCost.group == nil) else { return false }
            return fixedCost === selectedFixedCost || !(fixedCost.savingsGoals ?? []).contains { $0 !== goal && !$0.isArchived }
        }
    }

    private var noteSection: some View {
        Section("Notiz") {
            TextField("Optional", text: $note, axis: .vertical)
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !selectedIcon.isEmpty &&
        !selectedColorHex.isEmpty &&
        (type == .reserve || (targetAmount ?? 0) > 0) &&
        (!automaticBooking || (contributionAmount ?? 0) > 0)
    }

    @ViewBuilder
    private var selectedBudgetValue: some View {
        if let selectedBudget {
            HStack(spacing: 7) {
                Image(systemName: selectedBudget.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hexString: selectedBudget.iconColorHex))
                Text(selectedBudget.name)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            Text("Kein Budget")
                .foregroundStyle(.tint)
        }
    }

    private func save() {
        guard canSave else { return }

        let value = goal ?? SavingsGoal()
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.type = type
        value.iconName = selectedIcon
        value.iconColorHex = selectedColorHex
        value.targetAmount = type == .goal ? abs(targetAmount ?? 0) : nil
        value.contributionAmount = abs(contributionAmount ?? 0)
        value.frequency = frequency
        value.schedule = schedule
        value.anchorDate = Calendar.autoupdatingCurrent.startOfDay(for: anchorDate)
        value.dayOfMonth = min(max(Calendar.autoupdatingCurrent.component(.day, from: anchorDate), 1), 31)
        value.automaticBooking = automaticBooking
        value.note = note
        value.budget = selectedBudget
        value.fixedCost = type == .goal ? selectedFixedCost : nil
        value.group = group ?? selectedBudget?.group
        value.updatedAt = .now

        if goal == nil { modelContext.insert(value) }

        do {
            try modelContext.save()
            if value.automaticBooking {
                try SavingsGoalScheduler.processAutomaticBookings(
                    goals: [value],
                    transactions: transactions,
                    modelContext: modelContext
                )
            }
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}

private struct SavingsAmountRow: View {
    let title: String
    @Binding var amount: Decimal?
    let currencySymbol: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(
                "0,00",
                value: $amount,
                format: .number.precision(.fractionLength(0 ... 2))
            )
            .multilineTextAlignment(.trailing)
            .frame(minWidth: 100)

            Text(currencySymbol)
                .foregroundStyle(.secondary)
                .frame(minWidth: 22, alignment: .leading)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        }
    }
}
