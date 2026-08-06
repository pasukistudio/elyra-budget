import SwiftData
import SwiftUI

struct TransactionsView: View {
    @Environment(\.modelContext)
    private var modelContext

    @Query(
        sort: [
            SortDescriptor(
                \Transaction.date,
                order: .reverse
            ),
            SortDescriptor(
                \Transaction.createdAt,
                order: .reverse
            )
        ]
    )
    private var transactions: [Transaction]

    @State private var editingTransaction: Transaction?
    @State private var transactionToDelete: Transaction?

    var body: some View {
        Group {
            if transactions.isEmpty {
                emptyState
            } else {
                transactionList
            }
        }
        .sheet(
            isPresented: editingTransactionIsPresented
        ) {
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

    // MARK: - Leere Ansicht

    private var emptyState: some View {
        ContentUnavailableView(
            "Noch keine Buchungen",
            systemImage: "list.bullet.rectangle",
            description: Text(
                "Deine Einnahmen und Ausgaben erscheinen hier."
            )
        )
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .center
        )
    }

    // MARK: - Buchungsliste

    private var transactionList: some View {
        List {
            ForEach(
                groupedTransactions,
                id: \.date
            ) { group in
                Section {
                    ForEach(group.transactions) { transaction in
                        transactionRow(transaction)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingTransaction = transaction
                            }
                            .contextMenu {
                                transactionContextMenu(
                                    transaction
                                )
                            }
                            .swipeActions(
                                edge: .trailing,
                                allowsFullSwipe: false
                            ) {
                                deleteButton(transaction)
                                editButton(transaction)
                            }
                    }
                } header: {
                    Text(
                        sectionTitle(
                            for: group.date
                        )
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Buchungszeile

    private func transactionRow(
        _ transaction: Transaction
    ) -> some View {
        HStack(spacing: 12) {
            transactionIcon(transaction)

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text(transaction.title)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(
                        transaction.date,
                        format: .dateTime
                            .hour()
                            .minute()
                    )

                    if let budget = transaction.budget {
                        Text("•")

                        HStack(spacing: 4) {
                            Image(
                                systemName: budget.iconName
                            )
                            .foregroundStyle(
                                Color(
                                    hexString:
                                        budget.iconColorHex
                                )
                            )

                            Text(budget.name)
                                .foregroundStyle(
                                    Color(
                                        hexString:
                                            budget.iconColorHex
                                    )
                                )
                        }
                        .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(
                displayedAmount(
                    for: transaction
                ),
                format: .currency(
                    code: currencyCode
                )
            )
            .font(.headline)
            .foregroundStyle(
                amountColor(
                    for: transaction
                )
            )
        }
        .padding(.vertical, 4)
    }

    // MARK: - Buchungs-Icon

    private func transactionIcon(
        _ transaction: Transaction
    ) -> some View {
        let color = amountColor(
            for: transaction
        )

        return ZStack {
            RoundedRectangle(
                cornerRadius: 11,
                style: .continuous
            )
            .fill(
                color.opacity(0.14)
            )
            .frame(
                width: 44,
                height: 44
            )

            Image(
                systemName:
                    transaction.type.systemImage
            )
            .font(
                .system(
                    size: 17,
                    weight: .semibold
                )
            )
            .foregroundStyle(color)
        }
    }

    // MARK: - Beträge

    private func displayedAmount(
        for transaction: Transaction
    ) -> Decimal {
        transaction.signedAmount
    }

    private func amountColor(
        for transaction: Transaction
    ) -> Color {
        switch transaction.type {
        case .expense:
            return .red

        case .income:
            return .green

        case .refund:
            return .blue
        }
    }

    // MARK: - Gruppierung

    private var groupedTransactions:
        [TransactionDayGroup] {
        let calendar = Calendar.current

        let grouped = Dictionary(
            grouping: transactions
        ) { transaction in
            calendar.startOfDay(
                for: transaction.date
            )
        }

        return grouped
            .map { date, transactions in
                TransactionDayGroup(
                    date: date,
                    transactions:
                        transactions.sorted {
                            if $0.date == $1.date {
                                return $0.createdAt >
                                    $1.createdAt
                            }

                            return $0.date > $1.date
                        }
                )
            }
            .sorted {
                $0.date > $1.date
            }
    }

    private func sectionTitle(
        for date: Date
    ) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Heute"
        }

        if calendar.isDateInYesterday(date) {
            return "Gestern"
        }

        return date.formatted(
            .dateTime
                .weekday(.wide)
                .day()
                .month(.wide)
        )
    }

    // MARK: - Kontextmenü

    @ViewBuilder
    private func transactionContextMenu(
        _ transaction: Transaction
    ) -> some View {
        editButton(transaction)

        Divider()

        deleteButton(transaction)
    }

    private func editButton(
        _ transaction: Transaction
    ) -> some View {
        Button {
            editingTransaction = transaction
        } label: {
            Label(
                "Bearbeiten",
                systemImage: "pencil"
            )
        }
        .tint(.blue)
    }

    private func deleteButton(
        _ transaction: Transaction
    ) -> some View {
        Button(
            role: .destructive
        ) {
            transactionToDelete = transaction
        } label: {
            Label(
                "Löschen",
                systemImage: "trash"
            )
        }
    }

    // MARK: - Löschen

    private func deleteTransaction(
        _ transaction: Transaction
    ) {
        modelContext.delete(transaction)

        do {
            try modelContext.save()
            transactionToDelete = nil
        } catch {
            print(
                "Buchung konnte nicht gelöscht werden: \(error)"
            )
        }
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

    // MARK: - Währung

    private var currencyCode: String {
        Locale.current.currency?.identifier
            ?? "EUR"
    }
}

// MARK: - Tagesgruppe

private struct TransactionDayGroup {
    let date: Date
    let transactions: [Transaction]
}
