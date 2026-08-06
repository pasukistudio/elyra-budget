//
//  ArchivedBudgetsView.swift
//  ElyraBudget
//
//  Created by Pascal Smigielski on 06.08.26.
//


import SwiftData
import OSLog
import SwiftUI

struct ArchivedBudgetsView: View {
    @Environment(\.appCurrencyCode) private var currencyCode
    @Environment(\.dismiss)
    private var dismiss

    @Environment(\.modelContext)
    private var modelContext

    @Query
    private var allBudgets: [Budget]

    @State
    private var budgetToDelete: Budget?
    @State private var saveErrorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if archivedBudgets.isEmpty {
                    emptyState
                } else {
                    budgetList
                }
            }
            .navigationTitle("Archivierte Budgets")

            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif

            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
            .alert(
                "Budget endgültig löschen?",
                isPresented: deleteConfirmationIsPresented,
                presenting: budgetToDelete
            ) { budget in
                Button(
                    "Löschen",
                    role: .destructive
                ) {
                    deleteBudget(budget)
                }

                Button(
                    "Abbrechen",
                    role: .cancel
                ) {
                    budgetToDelete = nil
                }
            } message: { budget in
                Text(
                    "Das Budget „\(budget.name)“ wird dauerhaft gelöscht."
                )
            }
            .saveErrorAlert(message: $saveErrorMessage)
        }
    }

    // MARK: - Archivierte Budgets

    private var archivedBudgets: [Budget] {
        allBudgets
            .filter {
                $0.isArchived
            }
            .sorted {
                $0.updatedAt > $1.updatedAt
            }
    }

    // MARK: - Liste

    private var budgetList: some View {
        List {
            ForEach(archivedBudgets) { budget in
                budgetRow(budget)
                    .swipeActions(
                        edge: .leading,
                        allowsFullSwipe: true
                    ) {
                        restoreButton(budget)
                    }
                    .swipeActions(
                        edge: .trailing,
                        allowsFullSwipe: false
                    ) {
                        deleteButton(budget)
                    }
                    .contextMenu {
                        restoreButton(budget)
                        deleteButton(budget)
                    }
            }
        }
    }

    // MARK: - Leere Ansicht

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                "Keine archivierten Budgets",
                systemImage: "archivebox"
            )
        } description: {
            Text(
                "Archivierte Budgets werden hier angezeigt und können wiederhergestellt werden."
            )
        }
    }

    // MARK: - Budgetzeile

    private func budgetRow(
        _ budget: Budget
    ) -> some View {
        HStack(spacing: 12) {
            BudgetIconView(budget: budget, size: 40)

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(budget.name)
                    .font(.headline)
                    .lineLimit(1)

                if budget.limit > 0 {
                    Text(
                        budget.limit,
                        format: .currency(
                            code: currencyCode
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text("Kein Limit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(
                systemName: "archivebox.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - Buttons

    private func restoreButton(
        _ budget: Budget
    ) -> some View {
        Button {
            restoreBudget(budget)
        } label: {
            Label(
                "Wiederherstellen",
                systemImage: "arrow.uturn.backward"
            )
        }
        .tint(.green)
    }

    private func deleteButton(
        _ budget: Budget
    ) -> some View {
        Button(
            role: .destructive
        ) {
            budgetToDelete = budget
        } label: {
            Label(
                "Endgültig löschen",
                systemImage: "trash"
            )
        }
    }

    // MARK: - Wiederherstellen

    private func restoreBudget(
        _ budget: Budget
    ) {
        budget.isArchived = false
        budget.sortOrder = nextSortOrder
        budget.updatedAt = .now

        saveChanges(
            errorMessage:
                "Budget konnte nicht wiederhergestellt werden"
        )
    }

    private var nextSortOrder: Int {
        let activeBudgets = allBudgets.filter {
            !$0.isArchived
        }

        let highestSortOrder = activeBudgets
            .map(\.sortOrder)
            .max() ?? -1

        return highestSortOrder + 1
    }

    // MARK: - Löschen

    private func deleteBudget(
        _ budget: Budget
    ) {
        modelContext.delete(budget)

        saveChanges(
            errorMessage:
                "Budget konnte nicht gelöscht werden"
        )

        budgetToDelete = nil
    }

    // MARK: - Speichern

    private func saveChanges(
        errorMessage: String
    ) {
        do {
            try modelContext.save()
        } catch {
            AppLogger.persistence.error(
                "\(errorMessage): \(error)"
            )
            saveErrorMessage = errorMessage
        }
    }

    // MARK: - Löschen-Bestätigung

    private var deleteConfirmationIsPresented:
        Binding<Bool> {
        Binding(
            get: {
                budgetToDelete != nil
            },
            set: { isPresented in
                if !isPresented {
                    budgetToDelete = nil
                }
            }
        )
    }

    // MARK: - Währung

}
