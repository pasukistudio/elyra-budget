//
//  TransactionEditorView.swift
//  ElyraBudget
//
//  Created by Pascal Smigielski on 06.08.26.
//

import SwiftData
import OSLog
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
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

    @Environment(ProAccessManager.self)
    private var proAccess

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

    @Query private var savingsGoals: [SavingsGoal]
    @Query private var savingsContributions: [SavingsContribution]

    // MARK: - Eingaben

    @State private var title: String
    @State private var amount: Decimal?
    @State private var date: Date
    @State private var note: String
    @State private var receiptFilename: String?
    @State private var receiptData: Data?
    @State private var selectedType: TransactionType
    @State private var selectedBudget: Budget?

    // MARK: - Budgetmenü

    @State private var showingBudgetMenu = false
    @State private var showingReceiptImporter = false
    @State private var showingReceiptPreview = false
    @State private var showingProUpgrade = false
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
        _receiptFilename = State(
            initialValue: transaction?.receiptFilename
        )
        _receiptData = State(
            initialValue: transaction?.receiptData
                ?? transaction?.receiptFilename.flatMap(TransactionReceiptService.data(for:))
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

    private var effectiveGroup: BudgetGroup? {
        group ?? selectedBudget?.group
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
            .sheet(isPresented: $showingProUpgrade) {
                ProUpgradeView(feature: "Belege an Buchungen")
            }
            #if os(iOS)
            .sheet(isPresented: $showingReceiptPreview) {
                if let url = receiptURL {
                    ReceiptPreviewView(url: url)
                }
            }
            #endif
            .fileImporter(
                isPresented: $showingReceiptImporter,
                allowedContentTypes: [.image, .pdf],
                allowsMultipleSelection: false
            ) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let filename = try TransactionReceiptService.importFile(from: url)
                    receiptFilename = filename
                    receiptData = TransactionReceiptService.data(for: filename)
                } catch {
                    saveErrorMessage = "Der Beleg konnte nicht gespeichert werden."
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
                BudgetGroupContextRow(group: effectiveGroup)
                    .padding(.horizontal, 4)
                TransactionEditorNoteSection(
                    note: $note,
                    cardBackground: cardBackground
                )
                receiptSection
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

    private var receiptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TransactionEditorSectionHeader(title: "Beleg")
            if let url = receiptURL {
                VStack(spacing: 10) {
                    Button {
                        #if os(iOS)
                        showingReceiptPreview = true
                        #elseif os(macOS)
                        NSWorkspace.shared.open(url)
                        #endif
                    } label: {
                        HStack {
                            Label(url.lastPathComponent, systemImage: "doc.fill")
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "eye")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .buttonStyle(.plain)

                    HStack {
                        ShareLink(item: url) {
                            Label("Teilen", systemImage: "square.and.arrow.up")
                        }
                        Spacer()
                        Button("Entfernen", role: .destructive) {
                            self.receiptFilename = nil
                            self.receiptData = nil
                        }
                    }
                }
                .padding(16)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                Button {
                    if proAccess.hasPro {
                        showingReceiptImporter = true
                    } else {
                        showingProUpgrade = true
                    }
                } label: {
                    Label(
                        proAccess.hasPro ? "Foto oder PDF hinzufügen" : "Foto oder PDF hinzufügen · PRO",
                        systemImage: proAccess.hasPro ? "paperclip" : "lock.fill"
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var receiptURL: URL? {
        guard let receiptFilename else { return nil }
        if let url = TransactionReceiptService.url(for: receiptFilename),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        guard let receiptData else { return nil }
        return try? TransactionReceiptService.temporaryURL(
            for: receiptFilename,
            data: receiptData
        )
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

            let amountChanged = existingTransaction.amount != normalizedAmount
            existingTransaction.amount =
                normalizedAmount

            existingTransaction.date =
                date

            existingTransaction.note =
                cleanedNote

            existingTransaction.receiptFilename = receiptFilename
            existingTransaction.receiptData = receiptData

            existingTransaction.type =
                selectedType

            existingTransaction.budget =
                selectedBudget

            existingTransaction.group =
                effectiveGroup

            // Only reset the base amount when the user actually changed the amount.
            // Editing the title or note must preserve an existing round-up.
            if amountChanged {
                existingTransaction.roundUpOriginalAmount = nil
            }

            existingTransaction.updatedAt =
                .now

            do {
                try TransactionRoundUpService.applyIfNeeded(
                    to: existingTransaction,
                    group: effectiveGroup,
                    savingsGoals: savingsGoals,
                    contributions: savingsContributions,
                    modelContext: modelContext
                )
            } catch {
                saveErrorMessage = "Die Buchung konnte nicht aufgerundet werden."
                return
            }
        } else {
            let newTransaction = Transaction(
                title: cleanedTitle,
                amount: normalizedAmount,
                date: date,
                note: cleanedNote,
                type: selectedType,
                budget: selectedBudget,
                group: effectiveGroup
            )
            newTransaction.receiptFilename = receiptFilename
            newTransaction.receiptData = receiptData

            do {
                try TransactionRoundUpService.applyIfNeeded(
                    to: newTransaction,
                    group: effectiveGroup,
                    savingsGoals: savingsGoals,
                    contributions: savingsContributions,
                    modelContext: modelContext
                )
            } catch {
                saveErrorMessage = "Die Buchung konnte nicht aufgerundet werden."
                return
            }

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

#if os(iOS)
private struct ReceiptPreviewView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#endif

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
