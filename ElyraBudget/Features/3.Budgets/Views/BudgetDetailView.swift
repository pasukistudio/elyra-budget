import SwiftData
import OSLog
import SwiftUI

#if os(macOS)
import AppKit
#endif

struct BudgetDetailView: View {
    let budget: Budget
    @Environment(\.appCurrencyCode) private var currencyCode

    @Environment(\.dismiss)
    private var dismiss

    @Environment(\.modelContext)
    private var modelContext

    @Query
    private var userSettings: [UserSettings]

    @Query(
        sort: [
            SortDescriptor(\Transaction.date, order: .reverse),
            SortDescriptor(\Transaction.createdAt, order: .reverse)
        ]
    )
    private var allTransactions: [Transaction]

    @State private var selectedMonth: Date
    @State private var showingMonthPicker = false
    @State private var showingNewTransaction = false
    @State private var editingTransaction: Transaction?
    @State private var transactionToDelete: Transaction?

    init(budget: Budget, selectedDate: Date = .now) {
        self.budget = budget

        let monthStart = Calendar.current.dateInterval(
            of: .month,
            for: selectedDate
        )?.start ?? selectedDate

        _selectedMonth = State(
            initialValue: monthStart
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                budgetSummaryCard
                transactionsSection
            }
            .padding(.horizontal, 17)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(pageBackground)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                backButton
            }

            ToolbarItem(placement: .principal) {
                toolbarMonthNavigation
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewTransaction = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(effectiveAccentColor)
                }
                .accessibilityLabel("Neue Buchung")
            }
        }
        #else
        .toolbar {
            ToolbarItem(placement: .navigation) {
                backButton
            }
            ToolbarItem {
                Button {
                    showingNewTransaction = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Neue Buchung")
            }
        }
        #endif
        .tint(effectiveAccentColor)
        .sheet(isPresented: $showingMonthPicker) {
            MonthPickerSheet(
                selectedDate: $selectedMonth
            )
        }
        .sheet(isPresented: $showingNewTransaction) {
            TransactionEditorView(
                preselectedBudget: budget,
                initialDate: .now
            )
        }
        .sheet(isPresented: editingTransactionIsPresented) {
            if let editingTransaction {
                TransactionEditorView(
                    transaction: editingTransaction
                )
            }
        }
        .alert(
            "Buchung löschen?",
            isPresented: deleteConfirmationIsPresented,
            presenting: transactionToDelete
        ) { transaction in
            Button(
                "Löschen",
                role: .destructive
            ) {
                deleteTransaction(transaction)
            }

            Button(
                "Abbrechen",
                role: .cancel
            ) {
                transactionToDelete = nil
            }
        } message: { transaction in
            Text(
                "Die Buchung „\(transaction.title)“ wird dauerhaft gelöscht."
            )
        }
    }

    // MARK: - Zurück

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(
                    .system(
                        size: 17,
                        weight: .semibold
                    )
                )
                .foregroundStyle(effectiveAccentColor)
                .frame(
                    width: 30,
                    height: 30
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zurück")
    }

    // MARK: - Monatsnavigation

    private var toolbarMonthNavigation: some View {
        MonthNavigationControl(
            title: monthTitle,
            onPrevious: {
                moveMonth(by: -1)
            },
            onSelectDate: {
                showingMonthPicker = true
            },
            onNext: {
                moveMonth(by: 1)
            }
        )
        .tint(effectiveAccentColor)
    }

    // MARK: - Budgetübersicht

    private var budgetSummaryCard: some View {
        BudgetSummaryView(
            budget: budget,
            budgetColor: budgetColor,
            currencyCode: currencyCode,
            expenseAmount: expenseAmount,
            refundAmount: refundAmount,
            occupiedAmount: occupiedAmount,
            remainingAmount: remainingAmount,
            visualProgress: visualProgress
        )
    }

    // MARK: - Buchungen

    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Variable Buchungen")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showingNewTransaction = true
                } label: {
                    Image(systemName: "plus")
                        .font(
                            .system(
                                size: 15,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            effectiveAccentColor
                        )
                }
                .accessibilityLabel(
                    "Buchung hinzufügen"
                )
            }
            .padding(.horizontal, 4)

            if monthTransactions.isEmpty {
                emptyTransactionsCard
            } else {
                transactionCard
            }
        }
    }

    private var transactionCard: some View {
        LazyVStack(spacing: 0) {
            ForEach(
                Array(
                    monthTransactions.enumerated()
                ),
                id: \.element.persistentModelID
            ) { index, transaction in
                transactionButton(transaction)

                if index < monthTransactions.count - 1 {
                    Divider()
                        .padding(.leading, 72)
                        .padding(.trailing, 17)
                }
            }
        }
        .background(cardBackground)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 27,
                style: .continuous
            )
        )
    }

    private func transactionButton(
        _ transaction: Transaction
    ) -> some View {
        Button {
            editingTransaction = transaction
        } label: {
                    BudgetTransactionRowView(
                        transaction: transaction,
                        budgetColor: budgetColor,
                        currencyCode: currencyCode
                    )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                editingTransaction = transaction
            } label: {
                Label(
                    "Bearbeiten",
                    systemImage: "pencil"
                )
            }

            Divider()

            Button(role: .destructive) {
                transactionToDelete = transaction
            } label: {
                Label(
                    "Löschen",
                    systemImage: "trash"
                )
            }
        }
    }

    private var emptyTransactionsCard: some View {
        Text(
            "Keine variablen Buchungen in diesem Monat"
        )
        .font(.body)
        .foregroundStyle(.secondary)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(.horizontal, 17)
        .padding(.vertical, 20)
        .background(cardBackground)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 27,
                style: .continuous
            )
        )
    }

    // MARK: - Filterung

    private var budgetTransactions: [Transaction] {
        allTransactions.filter { transaction in
            transaction.budget?
                .persistentModelID
                == budget.persistentModelID
        }
    }

    private var monthTransactions: [Transaction] {
        return budgetTransactions.filter { transaction in
            transaction.date.isInSameMonth(as: selectedMonth)
        }
    }

    // MARK: - Monatswerte

    private var expenseAmount: Decimal {
        monthTransactions.reduce(.zero) {
            result,
            transaction in

            guard transaction.type == .expense else {
                return result
            }

            return result + transaction.amount
        }
    }

    private var refundAmount: Decimal {
        monthTransactions.reduce(.zero) {
            result,
            transaction in

            guard transaction.type == .refund else {
                return result
            }

            return result + transaction.amount
        }
    }

    private var occupiedAmount: Decimal {
        expenseAmount - refundAmount
    }

    private var remainingAmount: Decimal {
        budget.limit - occupiedAmount
    }

    private var visualProgress: Double {
        guard budget.limit > 0 else {
            return 0
        }

        let occupiedNumber =
            NSDecimalNumber(
                decimal: occupiedAmount
            )
            .doubleValue

        let limitNumber =
            NSDecimalNumber(
                decimal: budget.limit
            )
            .doubleValue

        guard limitNumber > 0 else {
            return 0
        }

        return min(
            max(
                occupiedNumber / limitNumber,
                0
            ),
            1
        )
    }

    // MARK: - Monatswechsel

    private func moveMonth(
        by value: Int
    ) {
        guard let newMonth =
            Calendar.current.date(
                byAdding: .month,
                value: value,
                to: selectedMonth
            )
        else {
            return
        }

        selectedMonth =
            Calendar.current.dateInterval(
                of: .month,
                for: newMonth
            )?.start ?? newMonth
    }

    // MARK: - Bindings

    private var editingTransactionIsPresented:
        Binding<Bool> {
        Binding(
            get: {
                editingTransaction != nil
            },
            set: { isPresented in
                if !isPresented {
                    editingTransaction = nil
                }
            }
        )
    }

    private var deleteConfirmationIsPresented:
        Binding<Bool> {
        Binding(
            get: {
                transactionToDelete != nil
            },
            set: { isPresented in
                if !isPresented {
                    transactionToDelete = nil
                }
            }
        )
    }

    // MARK: - Aktionen

    private func deleteTransaction(
        _ transaction: Transaction
    ) {
        modelContext.delete(transaction)

        do {
            try modelContext.save()
            transactionToDelete = nil
        } catch {
            AppLogger.persistence.error(
                "Buchung konnte nicht gelöscht werden: \(error)"
            )
        }
    }

    // MARK: - Akzentfarbe

    private var effectiveAccentColor: Color {
        guard let settings = userSettings.first else {
            return ColorPreset.blue.color
        }

        let accentColor = AppAccentColor(
            rawValue: settings.accentColorRawValue
        ) ?? .blue

        switch accentColor {
        case .custom:
            return Color(
                hexString: settings.customAccentHex
            )

        default:
            return accentColor.color
                ?? ColorPreset.blue.color
        }
    }

    // MARK: - Darstellung

    private var monthTitle: String {
        selectedMonth.formatted(
            .dateTime
                .month(.wide)
                .year()
        )
    }

    private var budgetColor: Color {
        Color(
            hexString: budget.iconColorHex
        )
    }

    private var cardBackground: Color {
        #if os(iOS)
        Color(
            uiColor:
                .secondarySystemGroupedBackground
        )
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    private var pageBackground: some View {
        #if os(iOS)
        return Color(
            uiColor: .systemGroupedBackground
        ).ignoresSafeArea()
        #else
        return Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
        #endif
    }

}
