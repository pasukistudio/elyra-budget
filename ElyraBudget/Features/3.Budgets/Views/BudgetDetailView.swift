import SwiftData
import OSLog
import SwiftUI

// swiftlint:disable type_body_length
struct BudgetDetailView: View {
    let budget: Budget

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

    init(budget: Budget) {
        self.budget = budget

        _selectedMonth = State(
            initialValue: Calendar.current.dateInterval(
                of: .month,
                for: .now
            )?.start ?? .now
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
        .tint(effectiveAccentColor)
        .sheet(isPresented: $showingMonthPicker) {
            MonthPickerSheet(
                selectedDate: $selectedMonth
            )
        }
        .sheet(isPresented: $showingNewTransaction) {
            TransactionEditorView(
                preselectedBudget: budget
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
        VStack(alignment: .leading, spacing: 15) {
            budgetHeader
            summaryValues

            Divider()

            occupiedAndRemainingValues

            if budget.limit > 0 {
                budgetProgress
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 16)
        .background(cardBackground)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 27,
                style: .continuous
            )
        )
    }

    private var budgetHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
                .fill(budgetColor.opacity(0.14))
                .frame(
                    width: 44,
                    height: 44
                )

                Image(
                    systemName: budget.iconName
                )
                .font(
                    .system(
                        size: 18,
                        weight: .semibold
                    )
                )
                .foregroundStyle(budgetColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(budget.name)
                    .font(.title3.bold())
                    .lineLimit(1)

                Text("Budgetübersicht")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Zusammenfassung

    private var summaryValues: some View {
        HStack(alignment: .top, spacing: 16) {
            summaryValue(
                title: "Variable Ausgaben",
                amount: expenseAmount,
                alignment: .leading,
                color: .primary
            )

            Spacer()

            summaryValue(
                title: "Rückerstattungen",
                amount: refundAmount,
                alignment: .trailing,
                color: refundAmount > 0
                    ? .green
                    : .primary
            )
        }
    }

    private func summaryValue(
        title: String,
        amount: Decimal,
        alignment: HorizontalAlignment,
        color: Color
    ) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(
                amount,
                format: .currency(
                    code: currencyCode
                )
            )
            .font(.headline)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    private var occupiedAndRemainingValues: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Gesamt belegt")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(
                    occupiedAmount,
                    format: .currency(
                        code: currencyCode
                    )
                )
                .font(.title3.bold())
                .foregroundStyle(
                    occupiedAmount < 0
                        ? Color.green
                        : Color.primary
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }

            Spacer()

            if budget.limit > 0 {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Verbleibend")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(
                        remainingAmount,
                        format: .currency(
                            code: currencyCode
                        )
                    )
                    .font(.title3.bold())
                    .foregroundStyle(
                        remainingAmount < 0
                            ? Color.red
                            : budgetColor
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
            }
        }
    }

    private var budgetProgress: some View {
        VStack(spacing: 7) {
            ProgressView(
                value: visualProgress
            )
            .tint(
                remainingAmount < 0
                    ? Color.red
                    : budgetColor
            )

            HStack {
                Text("Limit")

                Spacer()

                Text(
                    budget.limit,
                    format: .currency(
                        code: currencyCode
                    )
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
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
            transactionRow(transaction)
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

    private func transactionRow(
        _ transaction: Transaction
    ) -> some View {
        HStack(spacing: 13) {
            transactionIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(
                    transactionTypeText(
                        transaction
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text(
                    transaction.signedAmount,
                    format: .currency(
                        code: currencyCode
                    )
                )
                .font(.headline)
                .foregroundStyle(
                    transactionAmountColor(
                        transaction
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                Text(
                    transaction.date,
                    format: .dateTime
                        .day()
                        .month(.wide)
                        .year()
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 17)
        .frame(minHeight: 76)
        .contentShape(Rectangle())
    }

    private var transactionIcon: some View {
        ZStack {
            Circle()
                .fill(
                    budgetColor.opacity(0.14)
                )
                .frame(
                    width: 46,
                    height: 46
                )

            Image(
                systemName: budget.iconName
            )
            .font(
                .system(
                    size: 18,
                    weight: .semibold
                )
            )
            .foregroundStyle(budgetColor)
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
        guard let monthInterval =
            Calendar.current.dateInterval(
                of: .month,
                for: selectedMonth
            )
        else {
            return []
        }

        return budgetTransactions.filter { transaction in
            transaction.date >= monthInterval.start
                && transaction.date < monthInterval.end
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

    private func transactionTypeText(
        _ transaction: Transaction
    ) -> String {
        switch transaction.type {
        case .expense:
            return "\(budget.name) • Ausgabe"

        case .refund:
            return "\(budget.name) • Rückerstattung"

        case .income:
            return "\(budget.name) • Einnahme"
        }
    }

    private func transactionAmountColor(
        _ transaction: Transaction
    ) -> Color {
        switch transaction.type {
        case .expense:
            return .primary

        case .refund, .income:
            return .green
        }
    }

    private var budgetColor: Color {
        Color(
            hexString: budget.iconColorHex
        )
    }

    private var cardBackground: Color {
        Color(
            uiColor:
                .secondarySystemGroupedBackground
        )
    }

    private var pageBackground: some View {
        Color(
            uiColor: .systemGroupedBackground
        )
        .ignoresSafeArea()
    }

    private var currencyCode: String {
        Locale.current.currency?.identifier
            ?? "EUR"
    }
}
// swiftlint:enable type_body_length
