import SwiftData
import OSLog
import SwiftUI

struct TransactionsView: View {
    @Binding var selectedDate: Date
    @Binding var selectedGroup: BudgetGroup?
    @Environment(\.appCurrencyCode) private var currencyCode
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
    @State private var saveErrorMessage: String?

    private var displayedTransactions: [Transaction] {
        transactions.filter {
            $0.date.isInSameMonth(as: selectedDate)
                && (selectedGroup == nil || $0.effectiveGroup === selectedGroup)
        }
    }

    init(
        selectedDate: Binding<Date>,
        selectedGroup: Binding<BudgetGroup?> = .constant(nil)
    ) {
        _selectedDate = selectedDate
        _selectedGroup = selectedGroup
    }

    var body: some View {
        Group {
            if displayedTransactions.isEmpty {
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
                    transaction: editingTransaction,
                    group: selectedGroup
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
        .saveErrorAlert(message: $saveErrorMessage)
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
                        TransactionRowView(
                            transaction: transaction,
                            currencyCode: currencyCode
                        )
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
                    TransactionDaySectionHeader(date: group.date)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Gruppierung

    private var groupedTransactions:
        [TransactionDayGroup] {
        let calendar = Calendar.current

        let grouped = Dictionary(
            grouping: displayedTransactions
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
            AppLogger.persistence.error(
                "Buchung konnte nicht gelöscht werden: \(error)"
            )
            saveErrorMessage = "Die Buchung konnte nicht gelöscht werden."
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

}

// MARK: - Tagesgruppe

private struct TransactionDayGroup {
    let date: Date
    let transactions: [Transaction]
}
