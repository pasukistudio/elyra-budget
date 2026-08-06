import SwiftData
import OSLog
import SwiftUI

struct BudgetsView: View {
    @Binding var showingBudgetEditor: Bool
    @Binding var selectedDate: Date
    @Environment(\.appCurrencyCode) private var currencyCode

    @Environment(\.modelContext)
    private var modelContext

    @State private var editingBudget: Budget?
    @State private var budgetToDelete: Budget?
    @State private var saveErrorMessage: String?

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

    var body: some View {
        Group {
            if budgets.isEmpty {
                emptyState
            } else {
                budgetList
            }
        }
        .sheet(
            isPresented: editingBudgetIsPresented
        ) {
            if let editingBudget {
                BudgetEditorView(
                    budget: editingBudget
                )
            }
        }
        .alert(
            "Budget löschen?",
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

    // MARK: - Bearbeitungs-Sheet

    private var editingBudgetIsPresented: Binding<Bool> {
        Binding(
            get: {
                editingBudget != nil
            },
            set: { isPresented in
                if !isPresented {
                    editingBudget = nil
                }
            }
        )
    }

    // MARK: - Löschbestätigung

    private var deleteConfirmationIsPresented: Binding<Bool> {
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

    // MARK: - Budgetliste

    private var budgetList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(budgets) { budget in
                    NavigationLink {
                        BudgetDetailView(
                            budget: budget
                        )
                    } label: {
                        BudgetCardView(
                            budget: budget,
                            currencyCode: currencyCode,
                            selectedMonth: selectedDate
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        budgetContextMenu(budget)
                    }
                    .accessibilityAction(
                        named: "Budget öffnen"
                    ) {
                        // NavigationLink übernimmt das Öffnen.
                    }
                    .accessibilityAction(
                        named: "Budget bearbeiten"
                    ) {
                        editingBudget = budget
                    }
                    .accessibilityAction(
                        named: "Budget archivieren"
                    ) {
                        archiveBudget(budget)
                    }
                    .accessibilityAction(
                        named: "Budget löschen"
                    ) {
                        budgetToDelete = budget
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Leere Ansicht

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                "Noch keine Budgets",
                systemImage: "chart.pie"
            )
        } description: {
            Text(
                "Erstelle Budgets für Lebensmittel, Wohnen, Mobilität und weitere Bereiche."
            )
        } actions: {
            Button("Budget erstellen") {
                showingBudgetEditor = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Kontextmenü

    @ViewBuilder
    private func budgetContextMenu(
        _ budget: Budget
    ) -> some View {
        Button {
            editingBudget = budget
        } label: {
            Label(
                "Bearbeiten",
                systemImage: "pencil"
            )
        }

        Button {
            archiveBudget(budget)
        } label: {
            Label(
                "Archivieren",
                systemImage: "archivebox"
            )
        }

        Divider()

        Button(
            role: .destructive
        ) {
            budgetToDelete = budget
        } label: {
            Label(
                "Löschen",
                systemImage: "trash"
            )
        }
    }

    // MARK: - Archivieren

    private func archiveBudget(
        _ budget: Budget
    ) {
        budget.isArchived = true
        budget.updatedAt = .now

        do {
            try modelContext.save()
        } catch {
            AppLogger.persistence.error(
                "Budget konnte nicht archiviert werden: \(error)"
            )
            saveErrorMessage = "Das Budget konnte nicht archiviert werden."
        }
    }

    // MARK: - Löschen

    private func deleteBudget(
        _ budget: Budget
    ) {
        modelContext.delete(budget)

        do {
            try modelContext.save()
            budgetToDelete = nil
        } catch {
            AppLogger.persistence.error(
                "Budget konnte nicht gelöscht werden: \(error)"
            )
            saveErrorMessage = "Das Budget konnte nicht gelöscht werden."
        }
    }

    // MARK: - Währung

}
