import SwiftData
import SwiftUI

struct BudgetManagementView: View {
    @Environment(\.dismiss)
    private var dismiss

    @Environment(\.modelContext)
    private var modelContext

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

    @State private var editingBudget: Budget?
    @State private var budgetToDelete: Budget?

    @State private var draggedBudgetID: PersistentIdentifier?
    @State private var finishingBudgetID: PersistentIdentifier?
    @State private var dragStartIndex: Int?
    @State private var dragOffset: CGFloat = 0

    private let rowHeight: CGFloat = 74

    var body: some View {
        NavigationStack {
            Group {
                if budgets.isEmpty {
                    emptyState
                } else {
                    budgetList
                }
            }
            .navigationTitle("Budgets verwalten")

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
        }
    }

    // MARK: - Budgetliste

    private var budgetList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(
                    Array(budgets.enumerated()),
                    id: \.element.persistentModelID
                ) { index, budget in
                    budgetRow(
                        budget,
                        index: index
                    )

                    if index < budgets.count - 1 {
                        Divider()
                            .padding(.leading, 114)
                            .padding(.trailing, 18)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(
                .regularMaterial,
                in: RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
            )
            .padding(.horizontal)
            .padding(.top, 12)

            Text(
                "Ziehe den Griff links, um die Reihenfolge der Budgets zu ändern."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .padding(.horizontal, 34)
            .padding(.top, 8)
        }
        .scrollDisabled(
            draggedBudgetID != nil
        )
    }

    // MARK: - Leere Ansicht

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                "Keine Budgets",
                systemImage: "chart.pie"
            )
        } description: {
            Text(
                "Erstelle zuerst ein Budget, um es hier verwalten zu können."
            )
        }
    }

    // MARK: - Budgetzeile

    private func budgetRow(
        _ budget: Budget,
        index: Int
    ) -> some View {
        let isDragging =
            draggedBudgetID == budget.persistentModelID

        let shouldHideMenu =
            draggedBudgetID == budget.persistentModelID ||
            finishingBudgetID == budget.persistentModelID

        return HStack(spacing: 10) {
            dragHandle(
                budget,
                index: index
            )

            budgetIcon(budget)

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

            Spacer(minLength: 8)

            Group {
                if shouldHideMenu {
                    Color.clear
                        .frame(
                            width: 38,
                            height: 44
                        )
                } else {
                    budgetActionsMenu(budget)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: rowHeight)
        .background(
            isDragging
                ? Color.primary.opacity(0.05)
                : Color.clear
        )
        .contentShape(Rectangle())
        .offset(
            y: isDragging
                ? dragOffset
                : 0
        )
        .scaleEffect(
            isDragging
                ? 1.015
                : 1
        )
        .shadow(
            color:
                isDragging
                    ? .black.opacity(0.14)
                    : .clear,
            radius: isDragging ? 10 : 0,
            y: isDragging ? 5 : 0
        )
        .zIndex(
            isDragging
                ? 10
                : 0
        )
    }

    // MARK: - Sortiergriff

    private func dragHandle(
        _ budget: Budget,
        index: Int
    ) -> some View {
        Image(
            systemName: "line.3.horizontal"
        )
        .font(
            .system(
                size: 17,
                weight: .semibold
            )
        )
        .foregroundStyle(.tertiary)
        .frame(
            width: 32,
            height: 52
        )
        .contentShape(Rectangle())
        .gesture(
            reorderGesture(
                for: budget,
                index: index
            )
        )
        .accessibilityLabel(
            "\(budget.name) verschieben"
        )
        .accessibilityHint(
            "Nach oben oder unten ziehen"
        )
    }

    // MARK: - Verschiebegeste

    private func reorderGesture(
        for budget: Budget,
        index: Int
    ) -> some Gesture {
        DragGesture(
            minimumDistance: 4,
            coordinateSpace: .global
        )
        .onChanged { value in
            beginDraggingIfNeeded(
                budget,
                index: index
            )

            guard
                draggedBudgetID ==
                    budget.persistentModelID
            else {
                return
            }

            var transaction = Transaction()
            transaction.disablesAnimations = true

            withTransaction(transaction) {
                dragOffset = limitedDragOffset(
                    value.translation.height,
                    from: index
                )
            }
        }
        .onEnded { value in
            guard
                draggedBudgetID ==
                    budget.persistentModelID
            else {
                resetDragState()
                return
            }

            finishDragging(
                translation:
                    value.translation.height
            )
        }
    }

    private func beginDraggingIfNeeded(
        _ budget: Budget,
        index: Int
    ) {
        guard draggedBudgetID == nil else {
            return
        }

        draggedBudgetID =
            budget.persistentModelID

        dragStartIndex = index
        dragOffset = 0
    }

    // MARK: - Begrenzung der Bewegung

    private func limitedDragOffset(
        _ proposedOffset: CGFloat,
        from index: Int
    ) -> CGFloat {
        let maximumUpwardDistance =
            -CGFloat(index) * rowHeight

        let maximumDownwardDistance =
            CGFloat(
                budgets.count - index - 1
            ) * rowHeight

        return min(
            max(
                proposedOffset,
                maximumUpwardDistance
            ),
            maximumDownwardDistance
        )
    }

    // MARK: - Verschieben abschließen

    private func finishDragging(
        translation: CGFloat
    ) {
        guard
            let sourceIndex = dragStartIndex,
            budgets.indices.contains(sourceIndex),
            let movedBudgetID = draggedBudgetID
        else {
            resetDragState()
            return
        }

        let movedRows = Int(
            (
                translation / rowHeight
            ).rounded()
        )

        let targetIndex = min(
            max(
                sourceIndex + movedRows,
                budgets.startIndex
            ),
            budgets.index(
                before: budgets.endIndex
            )
        )

        finishingBudgetID = movedBudgetID

        guard targetIndex != sourceIndex else {
            resetDragState()

            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.12
            ) {
                finishingBudgetID = nil
            }

            return
        }

        var reorderedBudgets = budgets

        let movedBudget =
            reorderedBudgets.remove(
                at: sourceIndex
            )

        reorderedBudgets.insert(
            movedBudget,
            at: targetIndex
        )

        var transaction = Transaction()
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            updateSortOrder(
                for: reorderedBudgets
            )

            resetDragState()
        }

        saveChanges(
            errorMessage:
                "Budget-Reihenfolge konnte nicht gespeichert werden"
        )

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.15
        ) {
            finishingBudgetID = nil
        }
    }

    private func resetDragState() {
        draggedBudgetID = nil
        dragStartIndex = nil
        dragOffset = 0
    }

    // MARK: - Aktionsmenü

    private func budgetActionsMenu(
        _ budget: Budget
    ) -> some View {
        Menu {
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
        } label: {
            Image(
                systemName: "ellipsis.circle"
            )
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(
                width: 38,
                height: 44
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Aktionen für \(budget.name)"
        )
    }

    // MARK: - Budget-Icon

    private func budgetIcon(
        _ budget: Budget
    ) -> some View {
        let color = Color(
            hexString: budget.iconColorHex
        )

        return ZStack {
            RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
            .fill(
                color.opacity(0.15)
            )
            .frame(
                width: 42,
                height: 42
            )

            Image(
                systemName: budget.iconName
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

    // MARK: - Reihenfolge speichern

    private func updateSortOrder(
        for reorderedBudgets: [Budget]
    ) {
        for (
            index,
            budget
        ) in reorderedBudgets.enumerated() {
            budget.sortOrder = index
            budget.updatedAt = .now
        }
    }

    // MARK: - Archivieren

    private func archiveBudget(
        _ budget: Budget
    ) {
        budget.isArchived = true
        budget.updatedAt = .now

        let remainingBudgets =
            budgets.filter {
                $0.persistentModelID !=
                    budget.persistentModelID
            }

        updateSortOrder(
            for: remainingBudgets
        )

        saveChanges(
            errorMessage:
                "Budget konnte nicht archiviert werden"
        )
    }

    // MARK: - Löschen

    private func deleteBudget(
        _ budget: Budget
    ) {
        let remainingBudgets =
            budgets.filter {
                $0.persistentModelID !=
                    budget.persistentModelID
            }

        modelContext.delete(budget)

        updateSortOrder(
            for: remainingBudgets
        )

        saveChanges(
            errorMessage:
                "Budget konnte nicht gelöscht werden"
        )

        budgetToDelete = nil
    }

    // MARK: - Bearbeitungs-Sheet

    private var editingBudgetIsPresented:
        Binding<Bool> {
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

    // MARK: - Speichern

    private func saveChanges(
        errorMessage: String
    ) {
        do {
            try modelContext.save()
        } catch {
            print(
                "\(errorMessage): \(error)"
            )
        }
    }

    // MARK: - Währung

    private var currencyCode: String {
        Locale.current.currency?.identifier
            ?? "EUR"
    }
}
