//
//  TransactionEditorView.swift
//  ElyraBudget
//
//  Created by Pascal Smigielski on 06.08.26.
//

import SwiftData
import SwiftUI

#if os(iOS)
import UIKit
#endif

// swiftlint:disable type_body_length
struct TransactionEditorView: View {
    let transaction: Transaction?
    let preselectedBudget: Budget?

    // MARK: - Environment

    @Environment(\.dismiss)
    private var dismiss

    @Environment(\.modelContext)
    private var modelContext

    // MARK: - Budgets

    @Query(
        filter: #Predicate<Budget> {
            !$0.isArchived
        },
        sort: [
            SortDescriptor(\Budget.sortOrder),
            SortDescriptor(\Budget.createdAt)
        ]
    )
    private var budgets: [Budget]

    // MARK: - Eingaben

    @State private var title: String
    @State private var amount: Decimal?
    @State private var date: Date
    @State private var note: String
    @State private var selectedType: TransactionType
    @State private var selectedBudget: Budget?

    // MARK: - Budgetmenü

    @State private var showingBudgetMenu = false

    // MARK: - Initialisierung

    init(
        transaction: Transaction? = nil,
        preselectedBudget: Budget? = nil
    ) {
        self.transaction = transaction
        self.preselectedBudget = preselectedBudget

        _title = State(
            initialValue: transaction?.title ?? ""
        )

        _amount = State(
            initialValue: transaction?.amount
        )

        _date = State(
            initialValue: transaction?.date ?? .now
        )

        _note = State(
            initialValue: transaction?.note ?? ""
        )

        _selectedType = State(
            initialValue:
                transaction?.type ?? .expense
        )

        _selectedBudget = State(
            initialValue:
                transaction?.budget
                ?? preselectedBudget
        )
    }

    // MARK: - Hauptansicht

    var body: some View {
        NavigationStack {
            ZStack {
                editorContent

                if showingBudgetMenu {
                    dismissBackground

                    VStack {
                        Spacer()

                        HStack {
                            Spacer()

                            budgetMenu
                                .padding(.trailing, 25)
                                .padding(.bottom, 360)
                        }
                    }
                    .allowsHitTesting(true)
                    .zIndex(2)
                }
            }
            .background(editorBackground)
            .navigationTitle(
                transaction == nil
                    ? "Neue Buchung"
                    : "Buchung bearbeiten"
            )

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
                        saveTransaction()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Editor-Inhalt

    private var editorContent: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 26
            ) {
                amountCard
                detailsSection
                noteSection
            }
            .padding(.horizontal, 17)
            .padding(.top, 18)
            .padding(.bottom, 44)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .disabled(showingBudgetMenu)
    }

    // MARK: - Hintergrund

    private var editorBackground: some View {
        #if os(iOS)
        Color(
            uiColor: .systemGroupedBackground
        )
        .ignoresSafeArea()
        #else
        Color.secondary
            .opacity(0.06)
            .ignoresSafeArea()
        #endif
    }

    // MARK: - Betrag und Typ

    private var amountCard: some View {
        VStack(spacing: 0) {
            Picker(
                "Buchungstyp",
                selection: $selectedType
            ) {
                ForEach(
                    TransactionType.allCases
                ) { type in
                    Text(type.title)
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 15)

            Divider()
                .padding(.horizontal, 16)

            amountInput
        }
        .background(cardBackground)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 27,
                style: .continuous
            )
        )
    }

    private var amountInput: some View {
        ZStack {
            if amount == nil {
                Text("0,00 €")
                    .font(
                        .system(
                            size: 36,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.tertiary)
            }

            TextField(
                "",
                value: $amount,
                format: .number
                    .precision(
                        .fractionLength(0 ... 2)
                    )
            )
            .font(
                .system(
                    size: 36,
                    weight: .semibold,
                    design: .rounded
                )
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 15)

            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
        }
        .frame(minHeight: 84)
        .contentShape(Rectangle())
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            sectionTitle("Details")

            VStack(spacing: 0) {
                descriptionRow

                cardDivider

                budgetRow

                cardDivider

                dateRow
            }
            .background(cardBackground)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 27,
                    style: .continuous
                )
            )

            Text(budgetFooterText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var descriptionRow: some View {
        TextField(
            "Beschreibung",
            text: $title
        )
        .padding(.horizontal, 17)
        .frame(minHeight: 56)

        #if os(iOS)
        .textInputAutocapitalization(.sentences)
        #endif
    }

    // MARK: - Budgetzeile

    private var budgetRow: some View {
        Button {
            withAnimation(
                .easeInOut(duration: 0.16)
            ) {
                showingBudgetMenu.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                Text("Budget")
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                selectedBudgetValue

                Image(
                    systemName:
                        "chevron.up.chevron.down"
                )
                .font(
                    .system(
                        size: 11,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    showingBudgetMenu
                        ? Color.accentColor
                        : Color.secondary.opacity(0.55)
                )
            }
            .padding(.horizontal, 17)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ausgewähltes Budget

    @ViewBuilder
    private var selectedBudgetValue: some View {
        if let selectedBudget {
            HStack(spacing: 7) {
                Image(
                    systemName:
                        selectedBudget.iconName
                )
                .font(
                    .system(
                        size: 15,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    budgetColor(
                        for: selectedBudget
                    )
                )

                Text(selectedBudget.name)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            Text("Kein Budget")
                .foregroundStyle(
                    Color.accentColor
                )
                .lineLimit(1)
        }
    }

    // MARK: - Datum

    private var dateRow: some View {
        HStack(spacing: 12) {
            Text("Datum")
                .foregroundStyle(.primary)

            Spacer()

            DatePicker(
                "",
                selection: $date,
                displayedComponents: .date
            )
            .labelsHidden()
        }
        .padding(.horizontal, 17)
        .frame(minHeight: 56)
    }

    // MARK: - Notiz

    private var noteSection: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            sectionTitle("Notiz")

            TextField(
                "Optional",
                text: $note,
                axis: .vertical
            )
            .lineLimit(4 ... 8)
            .padding(.horizontal, 17)
            .padding(.vertical, 15)
            .frame(
                minHeight: 125,
                alignment: .topLeading
            )
            .background(cardBackground)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 27,
                    style: .continuous
                )
            )
        }
    }

    // MARK: - Hilfsansichten

    private func sectionTitle(
        _ text: String
    ) -> some View {
        Text(text)
            .font(
                .system(
                    size: 20,
                    weight: .bold
                )
            )
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    private var cardDivider: some View {
        Divider()
            .padding(.horizontal, 17)
    }

    private var cardBackground: Color {
        #if os(iOS)
        Color(
            uiColor:
                .secondarySystemGroupedBackground
        )
        #else
        Color.secondary.opacity(0.08)
        #endif
    }

    // MARK: - Hintergrund zum Schließen

    private var dismissBackground: some View {
        Color.black
            .opacity(0.001)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                closeBudgetMenu()
            }
            .zIndex(1)
    }

    // MARK: - Budgetmenü

    private var budgetMenu: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                budgetMenuRow(
                    title: "Kein Budget",
                    systemImage: nil,
                    color: .secondary,
                    isSelected:
                        selectedBudget == nil
                ) {
                    selectBudget(nil)
                }

                ForEach(
                    budgets,
                    id: \.persistentModelID
                ) { budget in
                    budgetMenuRow(
                        title: budget.name,
                        systemImage:
                            budget.iconName,
                        color:
                            budgetColor(
                                for: budget
                            ),
                        isSelected:
                            selectedBudget?
                                .persistentModelID
                            == budget.persistentModelID
                    ) {
                        selectBudget(budget)
                    }
                }
            }
            .padding(.vertical, 7)
        }
        .scrollIndicators(.hidden)
        .frame(
            width: 250,
            height: budgetMenuHeight
        )
        .background {
            menuMaterialBackground
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                menuBorderColor,
                lineWidth: 0.8
            )
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .shadow(
            color: .black.opacity(0.14),
            radius: 18,
            x: 0,
            y: 8
        )
        .transition(
            .opacity.combined(
                with: .scale(
                    scale: 0.98,
                    anchor: .bottomTrailing
                )
            )
        )
    }

    // MARK: - Apple-ähnlicher Menühintergrund

    @ViewBuilder
    private var menuMaterialBackground: some View {
        ZStack {
            #if os(iOS)
            SystemMaterialView(
                style: .systemChromeMaterial
            )

            Color(
                uiColor: .systemGray6
            )
            .opacity(0.38)

            Color.black
                .opacity(0.018)
            #else
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .fill(.regularMaterial)

            Color.primary
                .opacity(0.025)
            #endif
        }
    }

    private var menuBorderColor: Color {
        #if os(iOS)
        Color.white.opacity(0.52)
        #else
        Color.primary.opacity(0.10)
        #endif
    }

    // MARK: - Budgetmenü-Zeile

    private func budgetMenuRow(
        title: String,
        systemImage: String?,
        color: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(
            action: action
        ) {
            HStack(spacing: 10) {
                Image(
                    systemName: "checkmark"
                )
                .font(
                    .system(
                        size: 13,
                        weight: .semibold
                    )
                )
                .foregroundStyle(.primary)
                .opacity(
                    isSelected ? 1 : 0
                )
                .frame(width: 18)

                if let systemImage {
                    Image(
                        systemName: systemImage
                    )
                    .font(
                        .system(
                            size: 16,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(color)
                    .frame(width: 22)
                } else {
                    Color.clear
                        .frame(
                            width: 22,
                            height: 18
                        )
                }

                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(
                height: budgetMenuRowHeight
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Menüwerte

    private var budgetMenuRowHeight: CGFloat {
        42
    }

    private var budgetMenuHeight: CGFloat {
        let rowCount =
            budgets.count + 1

        let height =
            CGFloat(rowCount)
            * budgetMenuRowHeight
            + 14

        return min(
            height,
            315
        )
    }

    private func budgetColor(
        for budget: Budget
    ) -> Color {
        Color(
            hexString:
                budget.iconColorHex
        )
    }

    // MARK: - Auswahl

    private func selectBudget(
        _ budget: Budget?
    ) {
        selectedBudget = budget
        closeBudgetMenu()
    }

    private func closeBudgetMenu() {
        withAnimation(
            .easeInOut(duration: 0.16)
        ) {
            showingBudgetMenu = false
        }
    }

    // MARK: - Werte

    private var cleanedTitle: String {
        title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private var cleanedNote: String {
        note.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private var normalizedAmount: Decimal {
        guard let amount else {
            return 0
        }

        return amount < 0
            ? -amount
            : amount
    }

    private var canSave: Bool {
        !cleanedTitle.isEmpty
            && normalizedAmount > 0
    }

    private var budgetFooterText: String {
        switch selectedType {
        case .expense:
            return "Ausgaben erhöhen den verwendeten Betrag des ausgewählten Budgets."

        case .refund:
            return "Rückerstattungen reduzieren den verwendeten Betrag des ausgewählten Budgets."

        case .income:
            return "Einnahmen beeinflussen das Budget nicht."
        }
    }

    // MARK: - Speichern

    private func saveTransaction() {
        guard canSave else {
            return
        }

        if let existingTransaction =
            transaction {
            existingTransaction.title =
                cleanedTitle

            existingTransaction.amount =
                normalizedAmount

            existingTransaction.date =
                date

            existingTransaction.note =
                cleanedNote

            existingTransaction.type =
                selectedType

            existingTransaction.budget =
                selectedBudget

            existingTransaction.updatedAt =
                .now
        } else {
            let newTransaction = Transaction(
                title: cleanedTitle,
                amount: normalizedAmount,
                date: date,
                note: cleanedNote,
                type: selectedType,
                budget: selectedBudget
            )

            modelContext.insert(
                newTransaction
            )
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print(
                "Buchung konnte nicht gespeichert werden: \(error)"
            )
        }
    }
}
// swiftlint:enable type_body_length

// MARK: - UIKit-Systemmaterial

#if os(iOS)

private struct SystemMaterialView:
    UIViewRepresentable {

    let style: UIBlurEffect.Style

    func makeUIView(
        context: Context
    ) -> UIVisualEffectView {
        let effect = UIBlurEffect(
            style: style
        )

        let view = UIVisualEffectView(
            effect: effect
        )

        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false

        return view
    }

    func updateUIView(
        _ uiView: UIVisualEffectView,
        context: Context
    ) {
        uiView.effect = UIBlurEffect(
            style: style
        )
    }
}

#endif
