import SwiftData
import SwiftUI

struct BudgetEditorView: View {
    let budget: Budget?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ProAccessManager.self) private var proAccess

    @State private var name: String
    @State private var limit: Decimal?

    @State private var selectedIcon: String
    @State private var selectedColorHex: String

    @State private var includesFixedCosts: Bool
    @State private var showingIconPicker = false

    // MARK: - Initialisierung

    init(
        budget: Budget? = nil
    ) {
        self.budget = budget

        let initialLimit: Decimal?

        if let budget, budget.limit > 0 {
            initialLimit = budget.limit
        } else {
            initialLimit = nil
        }

        _name = State(
            initialValue: budget?.name ?? ""
        )

        _limit = State(
            initialValue: initialLimit
        )

        _selectedIcon = State(
            initialValue: budget?.iconName ?? "cart.fill"
        )

        _selectedColorHex = State(
            initialValue: budget?.iconColorHex ?? "#FF9500"
        )

        _includesFixedCosts = State(
            initialValue: budget?.includesFixedCosts ?? true
        )
    }

    // MARK: - Grid-Konfiguration

    private let iconColumns = Array(
        repeating: GridItem(
            .flexible(),
            spacing: 12
        ),
        count: 5
    )

    private let colorColumns = Array(
        repeating: GridItem(
            .flexible(),
            spacing: 8
        ),
        count: 5
    )

    // MARK: - Häufige Budget-Icons

    private let featuredIcons =
        CategoryIconLibrary.budgetFeatured

    // MARK: - Verfügbare Farben

    private let availableColors = ColorPreset.allCases

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                budgetSection
                appearanceSection
                calculationSection
            }
            .navigationTitle(
                budget == nil
                    ? "Neues Budget"
                    : "Budget bearbeiten"
            )

            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .sheet(
                    isPresented: $showingIconPicker
                ) {
                    IconPickerView(
                        selectedIcon: $selectedIcon
                    )
                }
            #endif

                .toolbar {
                    ToolbarItem(
                        placement: .cancellationAction
                    ) {
                        Button("Abbrechen") {
                            dismiss()
                        }
                    }

                    ToolbarItem(
                        placement: .confirmationAction
                    ) {
                        Button("Speichern") {
                            saveBudget()
                        }
                        .disabled(!canSave)
                    }
                }
        }
    }

    // MARK: - Vorschau

    private var previewSection: some View {
        Section("Vorschau") {
            HStack(spacing: 14) {
                budgetIcon(
                    iconName: selectedIcon,
                    colorHex: selectedColorHex,
                    size: 48
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        cleanedName.isEmpty
                            ? String(localized: "Budgetname")
                            : cleanedName
                    )
                    .font(.headline)
                    .lineLimit(1)

                    Text("Ausgaben: 0,00 €")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("Limit")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let limit, limit > 0 {
                        Text(
                            limit,
                            format: .currency(
                                code: currencyCode
                            )
                        )
                        .font(.headline)
                    } else {
                        Text("Kein Limit")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Budget

    private var budgetSection: some View {
        Section {
            TextField(
                "Name",
                text: $name
            )

            #if os(iOS)
            .textInputAutocapitalization(.words)
            #endif

            TextField(
                "Kein Limit",
                value: $limit,
                format: .number
                    .precision(
                        .fractionLength(0 ... 2)
                    )
            )

            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
        } header: {
            Text("Budget")
        } footer: {
            Text(
                "Das Limit ist optional. Ohne Limit dient das Budget nur als Kategorie für deine Buchungen."
            )
        }
    }

    // MARK: - Darstellung

    private var appearanceSection: some View {
        Section("Darstellung") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Icon")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: iconColumns,
                    spacing: 12
                ) {
                    ForEach(
                        featuredIcons,
                        id: \.self
                    ) { iconName in
                        iconButton(iconName)
                    }
                }

                Button {
                    showingIconPicker = true
                } label: {
                    HStack {
                        Text(
                            "Weitere Icons"
                        )
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

                LazyVGrid(
                    columns: colorColumns,
                    spacing: 10
                ) {
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

    // MARK: - Berechnung

    private var calculationSection: some View {
        Section {
            Toggle(
                "Fixkosten anrechnen",
                isOn: $includesFixedCosts
            )
        } footer: {
            Text(
                "Ist diese Option aktiviert, werden später auch Fixkosten berücksichtigt, die diesem Budget zugeordnet sind."
            )
        }
    }

    // MARK: - Icon-Auswahl

    private func iconButton(
        _ iconName: String
    ) -> some View {
        let isSelected = selectedIcon == iconName

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedIcon = iconName
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isSelected
                            ? selectedColor.opacity(0.18)
                            : Color.secondary.opacity(0.08)
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: iconName)
                    .font(
                        .system(
                            size: 18,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        isSelected
                            ? selectedColor
                            : .secondary
                    )

                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            selectedColor,
                            lineWidth: 2
                        )
                        .frame(width: 48, height: 48)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Icon auswählen")
        .accessibilityAddTraits(
            isSelected ? .isSelected : []
        )
    }

    // MARK: - Farbauswahl

    private func colorButton(
        _ preset: ColorPreset
    ) -> some View {
        let isSelected =
            selectedColorHex == preset.hex

        return Button {
            withAnimation(
                .easeInOut(duration: 0.15)
            ) {
                selectedColorHex = preset.hex
            }
        } label: {
            ZStack {
                Circle()
                    .fill(preset.color)
                    .frame(
                        width: 36,
                        height: 36
                    )

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(
                            .system(
                                size: 14,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(.white)
                }
            }
            .frame(
                width: 44,
                height: 44
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.title)
        .accessibilityAddTraits(
            isSelected ? .isSelected : []
        )
    }

    // MARK: - Eigene Farbe

    @ViewBuilder
    private var customColorRow: some View {
        if proAccess.hasPro {
            ColorPicker(
                selection: customColorBinding,
                supportsOpacity: false
            ) {
                Text("Eigene Farbe")
            }
            .padding(.trailing, 17)
        } else {
            Button {
                // Später Pro-Ansicht öffnen
            } label: {
                HStack(spacing: 10) {
                    Text("Eigene Farbe")
                        .foregroundStyle(.primary)

                    Spacer()

                    Text("PRO")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            .tint.opacity(0.15),
                            in: Capsule()
                        )

                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .padding(.trailing, 22)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Eigene Farbauswahl

    private var customColorBinding: Binding<Color> {
        Binding(
            get: {
                selectedColor
            },
            set: { newColor in
                guard let hex = newColor.toHex() else {
                    return
                }

                selectedColorHex = hex
            }
        )
    }

    // MARK: - Budget-Icon

    private func budgetIcon(
        iconName: String,
        colorHex: String,
        size: CGFloat
    ) -> some View {
        let color = Color(hexString: colorHex)

        return ZStack {
            RoundedRectangle(
                cornerRadius: size * 0.26
            )
            .fill(color.opacity(0.16))
            .frame(width: size, height: size)

            Image(systemName: iconName)
                .font(
                    .system(
                        size: size * 0.4,
                        weight: .semibold
                    )
                )
                .foregroundStyle(color)
        }
    }

    // MARK: - Werte

    private var cleanedName: String {
        name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private var selectedColor: Color {
        Color(hexString: selectedColorHex)
    }

    private var normalizedLimit: Decimal {
        guard let limit, limit > 0 else {
            return 0
        }

        return limit
    }

    private var canSave: Bool {
        !cleanedName.isEmpty &&
            !selectedIcon.isEmpty &&
            !selectedColorHex.isEmpty
    }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "EUR"
    }

    // MARK: - Speichern

    private func saveBudget() {
        guard canSave else {
            return
        }

        if let existingBudget = budget {
            existingBudget.name = cleanedName
            existingBudget.iconName = selectedIcon
            existingBudget.iconColorHex = selectedColorHex
            existingBudget.limit = normalizedLimit
            existingBudget.includesFixedCosts = includesFixedCosts
            existingBudget.updatedAt = .now
        } else {
            let newBudget = Budget(
                name: cleanedName,
                iconName: selectedIcon,
                iconColorHex: selectedColorHex,
                limit: normalizedLimit,
                includesFixedCosts: includesFixedCosts
            )

            modelContext.insert(newBudget)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print(
                "Budget konnte nicht gespeichert werden: \(error)"
            )
        }
    }
}
