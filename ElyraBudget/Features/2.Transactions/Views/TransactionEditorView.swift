//
//  TransactionEditorView.swift
//  ElyraBudget
//
//  Created by Pascal Smigielski on 06.08.26.
//

import SwiftData
import OSLog
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct TransactionEditorView: View {
    let transaction: Transaction?
    let preselectedBudget: Budget?
    let initialDate: Date
    let group: BudgetGroup?

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
    @State private var saveErrorMessage: String?

    // MARK: - Initialisierung

    init(
        transaction: Transaction? = nil,
        preselectedBudget: Budget? = nil,
        initialDate: Date = .now,
        group: BudgetGroup? = nil
    ) {
        self.transaction = transaction
        self.preselectedBudget = preselectedBudget
        self.initialDate = initialDate
        self.group = group ?? transaction?.group

        _title = State(
            initialValue: transaction?.title ?? ""
        )

        _amount = State(
            initialValue: transaction?.amount
        )

        _date = State(
            initialValue: transaction?.date ?? initialDate
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

    private var visibleBudgets: [Budget] {
        budgets.filter { budget in
            group == nil || budget.group === group
        }
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

                            TransactionEditorBudgetMenu(
                                budgets: visibleBudgets,
                                selectedBudget: $selectedBudget,
                                isPresented: $showingBudgetMenu
                            )
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
            .saveErrorAlert(message: $saveErrorMessage)
        }
    }

    // MARK: - Editor-Inhalt

    private var editorContent: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 26
            ) {
                TransactionEditorAmountSection(
                    amount: $amount,
                    selectedType: $selectedType,
                    cardBackground: cardBackground
                )
                TransactionEditorDetailsSection(
                    title: $title,
                    date: $date,
                    selectedBudget: $selectedBudget,
                    showingBudgetMenu: $showingBudgetMenu,
                    footerText: budgetFooterText,
                    cardBackground: cardBackground
                )
                TransactionEditorNoteSection(
                    note: $note,
                    cardBackground: cardBackground
                )
            }
            .padding(.horizontal, 17)
            .padding(.top, 18)
            .padding(.bottom, 44)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
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

    // MARK: - Hilfsansichten

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

            existingTransaction.group =
                group ?? selectedBudget?.group

            existingTransaction.updatedAt =
                .now
        } else {
            let newTransaction = Transaction(
                title: cleanedTitle,
                amount: normalizedAmount,
                date: date,
                note: cleanedNote,
                type: selectedType,
                budget: selectedBudget,
                group: group ?? selectedBudget?.group
            )

            modelContext.insert(
                newTransaction
            )
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            AppLogger.persistence.error(
                "Buchung konnte nicht gespeichert werden: \(error)"
            )
            saveErrorMessage = "Die Buchung konnte nicht gespeichert werden."
        }
    }

}
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
