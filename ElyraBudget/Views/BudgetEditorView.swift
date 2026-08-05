import SwiftUI
import SwiftData

struct BudgetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var limit: Decimal?

    @State private var selectedIcon = "cart.fill"
    @State private var selectedColorHex = "#FF9500"

    @State private var includesFixedCosts = true

    private let iconColumns = [
        GridItem(.adaptive(minimum: 52), spacing: 12)
    ]

    private let colorColumns = [
        GridItem(.adaptive(minimum: 44), spacing: 12)
    ]

    private let availableIcons = [
        "cart.fill",
        "house.fill",
        "car.fill",
        "fuelpump.fill",
        "fork.knife",
        "cup.and.saucer.fill",
        "gamecontroller.fill",
        "film.fill",
        "airplane",
        "tram.fill",
        "cross.case.fill",
        "pawprint.fill",
        "tshirt.fill",
        "gift.fill",
        "graduationcap.fill",
        "phone.fill",
        "bolt.fill",
        "wifi",
        "figure.run",
        "ellipsis"
    ]

    private let availableColors = [
        "#FF9500",
        "#FF3B30",
        "#FF2D55",
        "#AF52DE",
        "#5856D6",
        "#007AFF",
        "#32ADE6",
        "#00C7BE",
        "#34C759",
        "#8E8E93"
    ]

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                budgetSection
                appearanceSection
                calculationSection
            }
            .navigationTitle("Neues Budget")

#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
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
                        .fractionLength(0...2)
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
                        availableIcons,
                        id: \.self
                    ) { iconName in
                        iconButton(iconName)
                    }
                }
            }
            .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 12) {
                Text("Icon-Farbe")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: colorColumns,
                    spacing: 12
                ) {
                    ForEach(
                        availableColors,
                        id: \.self
                    ) { colorHex in
                        colorButton(colorHex)
                    }
                }
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
        _ colorHex: String
    ) -> some View {
        let color = Color(hexString: colorHex)
        let isSelected =
            selectedColorHex == colorHex

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedColorHex = colorHex
            }
        } label: {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 36, height: 36)

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
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Farbe auswählen")
        .accessibilityAddTraits(
            isSelected ? .isSelected : []
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

        let budget = Budget(
            name: cleanedName,
            iconName: selectedIcon,
            iconColorHex: selectedColorHex,
            limit: normalizedLimit,
            includesFixedCosts: includesFixedCosts
        )

        modelContext.insert(budget)

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
