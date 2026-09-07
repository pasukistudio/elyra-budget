import SwiftData
import OSLog
import SwiftUI
import UniformTypeIdentifiers

enum TransactionToolbarAction: Equatable {
    case exportCSV
    case exportPDF
    case importCSV
    case recurringTransactions
}

private enum TransactionBudgetFilter: Hashable {
    case all
    case withoutBudget
    case budget(UUID)
}

struct TransactionsView: View {
    @Binding var selectedDate: Date
    @Binding var selectedGroup: BudgetGroup?
    @Binding var requestedToolbarAction: TransactionToolbarAction?
    @Binding var showingSearch: Bool
    let onNewTransaction: () -> Void
    @Environment(\.appCurrencyCode) private var currencyCode
    @Environment(ProAccessManager.self) private var proAccess
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
    @Query private var budgets: [Budget]
    @Query private var budgetGroups: [BudgetGroup]
    @Query private var savingsGoals: [SavingsGoal]
    @Query private var savingsContributions: [SavingsContribution]

    @State private var editingTransaction: Transaction?
    @State private var transactionToDelete: Transaction?
    @State private var saveErrorMessage: String?
    @State private var showingProUpgrade = false
    @State private var exportFile: ExportFile?
    @State private var exportErrorMessage: String?
    @State private var showingImporter = false
    @State private var importRows: [CSVImportRow] = []
    @State private var showingImportPreview = false
    @State private var importErrorMessage: String?
    @State private var showingRecurringTransactions = false
    @State private var dayFilterEnabled = false
    @State private var selectedDay = Date()
    @State private var showingFilters = false
    @State private var selectedBudgetFilter: TransactionBudgetFilter = .all
    @State private var selectedTransactionType: TransactionType?
    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool

    private var displayedTransactions: [Transaction] {
        let monthTransactions = transactions.filter {
            $0.date.isInSameMonth(as: selectedDate)
                && (selectedGroup == nil || $0.effectiveGroup === selectedGroup)
        }

        return monthTransactions.filter { transaction in
            let matchesDay = !dayFilterEnabled || Calendar.autoupdatingCurrent.isDate(
                transaction.date,
                inSameDayAs: selectedDay
            )
            let matchesBudget: Bool = switch selectedBudgetFilter {
            case .all:
                true
            case .withoutBudget:
                transaction.budget == nil
            case .budget(let budgetID):
                transaction.budget?.id == budgetID
            }
            let matchesType = selectedTransactionType == nil
                || transaction.type == selectedTransactionType
            let matchesSearch = normalizedSearchText.isEmpty
                || searchableText(for: transaction).contains(normalizedSearchText)
            return matchesDay && matchesBudget && matchesType && matchesSearch
        }
    }

    private var normalizedSearchText: String {
        searchText
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            .filter { !$0.isWhitespace }
    }

    private func searchableText(for transaction: Transaction) -> String {
        [
            transaction.title,
            transaction.note,
            transaction.budget?.name ?? "",
            transaction.type.title
        ]
        .joined(separator: " ")
        .folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        .filter { !$0.isWhitespace }
    }

    private var availableBudgetFilters: [Budget] {
        budgets
            .filter { selectedGroup == nil || $0.group === selectedGroup }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var selectedMonthDateRange: ClosedRange<Date> {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.date(
            from: calendar.dateComponents([.year, .month], from: selectedDate)
        ) ?? selectedDate
        let end = calendar.date(
            byAdding: DateComponents(month: 1, second: -1),
            to: start
        ) ?? selectedDate
        return start ... end
    }

    init(
        selectedDate: Binding<Date>,
        selectedGroup: Binding<BudgetGroup?> = .constant(nil),
        requestedToolbarAction: Binding<TransactionToolbarAction?> = .constant(nil),
        showingSearch: Binding<Bool> = .constant(false),
        onNewTransaction: @escaping () -> Void = {}
    ) {
        _selectedDate = selectedDate
        _selectedGroup = selectedGroup
        _requestedToolbarAction = requestedToolbarAction
        _showingSearch = showingSearch
        self.onNewTransaction = onNewTransaction
    }

    var body: some View {
        VStack(spacing: 0) {
            dayFilterBar

            Group {
                if displayedTransactions.isEmpty {
                    emptyState
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    transactionList
                        .transition(.opacity)
                }
            }
        }
        .animation(.snappy(duration: 0.3), value: displayedTransactions.isEmpty)
        .onChange(of: showingSearch) { _, isPresented in
            searchFieldFocused = isPresented
        }
        .onChange(of: selectedDate) { _, newDate in
            guard dayFilterEnabled else { return }
            selectedDay = newDate
        }
        .onChange(of: selectedGroup?.id) { _, _ in
            selectedBudgetFilter = .all
        }
        .sheet(isPresented: $showingFilters) {
            filterSheet
        }
        .onChange(of: requestedToolbarAction) { _, action in
            guard let action else { return }
            handleToolbarAction(action)
            requestedToolbarAction = nil
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
        .sheet(isPresented: $showingProUpgrade) {
            ProUpgradeView(feature: "CSV- und PDF-Export")
        }
        .sheet(item: $exportFile) { file in
            NavigationStack {
                VStack(spacing: 18) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                    Text("Export bereit")
                        .font(.title3.bold())
                    Text("Teile die Datei oder speichere sie in der Dateien-App.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    ShareLink(item: file.url) {
                        Label("Datei teilen", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .navigationTitle("Export")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
            }
        }
        .alert("Export nicht möglich", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("OK") { exportErrorMessage = nil }
        } message: {
            Text(exportErrorMessage ?? "Die Datei konnte nicht erstellt werden.")
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, .text, .data],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showingImportPreview) {
            CSVImportPreviewView(
                rows: importRows,
                onImport: importRowsIntoStore,
                onCancel: { showingImportPreview = false }
            )
        }
        .sheet(isPresented: $showingRecurringTransactions) {
            RecurringTransactionsView(selectedGroup: selectedGroup)
        }
        .alert("CSV-Import nicht möglich", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("OK") { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "Die Datei konnte nicht importiert werden.")
        }
    }

    private var dayFilterBar: some View {
        HStack {
            if showingSearch {
                TextField("Buchungen suchen", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFieldFocused)
                    .submitLabel(.search)

                Button {
                    searchText = ""
                    showingSearch = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Suche schließen")
            } else {
                Button {
                    if !dayFilterEnabled {
                        selectedDay = selectedDate
                    }
                    showingFilters = true
                } label: {
                    Label(
                        "Filtern",
                        systemImage: hasActiveFilters
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
                    )
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 12)

                Button {
                    showingSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.medium))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Buchungen suchen")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var hasActiveFilters: Bool {
        dayFilterEnabled
            || selectedBudgetFilter != .all
            || selectedTransactionType != nil
    }

    private var filterSheet: some View {
        NavigationStack {
            List {
                Section("Tage") {
                    Button {
                        dayFilterEnabled = false
                    } label: {
                        filterRow(
                            title: "Alle Tage",
                            systemImage: "calendar",
                            isSelected: !dayFilterEnabled
                        )
                    }

                    DatePicker(
                        "Tag auswählen",
                        selection: $selectedDay,
                        in: selectedMonthDateRange,
                        displayedComponents: [.date]
                    )
                    .onChange(of: selectedDay) { _, _ in
                        dayFilterEnabled = true
                    }
                }

                Section("Budget") {
                    Button {
                        selectedBudgetFilter = .all
                    } label: {
                        filterRow(
                            title: "Alle Budgets",
                            systemImage: "square.grid.2x2",
                            isSelected: selectedBudgetFilter == .all
                        )
                    }

                    Button {
                        selectedBudgetFilter = .withoutBudget
                    } label: {
                        filterRow(
                            title: "Ohne Budget",
                            systemImage: "tray",
                            isSelected: selectedBudgetFilter == .withoutBudget
                        )
                    }

                    ForEach(availableBudgetFilters, id: \.id) { budget in
                        Button {
                            selectedBudgetFilter = .budget(budget.id)
                        } label: {
                            filterRow(
                                title: budget.name,
                                systemImage: budget.iconName,
                                isSelected: selectedBudgetFilter == .budget(budget.id)
                            )
                        }
                    }
                }

                Section("Buchungsart") {
                    Button {
                        selectedTransactionType = nil
                    } label: {
                        filterRow(
                            title: "Alle Arten",
                            systemImage: "arrow.up.arrow.down",
                            isSelected: selectedTransactionType == nil
                        )
                    }

                    ForEach(TransactionType.allCases) { type in
                        Button {
                            selectedTransactionType = type
                        } label: {
                            filterRow(
                                title: type.title,
                                systemImage: type.systemImage,
                                isSelected: selectedTransactionType == type
                            )
                        }
                    }
                }

                if hasActiveFilters {
                    Section {
                        Button("Filter zurücksetzen", role: .destructive) {
                            dayFilterEnabled = false
                            selectedBudgetFilter = .all
                            selectedTransactionType = nil
                        }
                    }
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        showingFilters = false
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func filterRow(
        title: String,
        systemImage: String,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 12)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .foregroundStyle(isSelected ? Color.accentColor : .primary)
    }

    private func export(format: TransactionExportFormat) {
        guard proAccess.hasPro else {
            showingProUpgrade = true
            return
        }

        do {
            let url = try TransactionExportService.write(
                transactions: displayedTransactions,
                month: selectedDate,
                currencyCode: currencyCode,
                format: format
            )
            exportFile = ExportFile(url: url)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func handleToolbarAction(_ action: TransactionToolbarAction) {
        switch action {
        case .exportCSV:
            export(format: .csv)
        case .exportPDF:
            export(format: .pdf)
        case .importCSV:
            beginImport()
        case .recurringTransactions:
            if proAccess.hasPro {
                showingRecurringTransactions = true
            } else {
                showingProUpgrade = true
            }
        }
    }

    private var transactionToolsMenu: some View {
        Menu {
            Button {
                export(format: .csv)
            } label: {
                Label("CSV exportieren", systemImage: "tablecells")
            }
            Button {
                export(format: .pdf)
            } label: {
                Label("PDF exportieren", systemImage: "doc.richtext")
            }
            Divider()
            Button {
                beginImport()
            } label: {
                Label("CSV importieren", systemImage: "square.and.arrow.down")
            }
            Button {
                if proAccess.hasPro {
                    showingRecurringTransactions = true
                } else {
                    showingProUpgrade = true
                }
            } label: {
                Label("Wiederkehrende Buchungen", systemImage: "arrow.triangle.2.circlepath")
            }
        } label: {
            Label("Import / Export", systemImage: "arrow.up.arrow.down")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel("Import und Export")
    }

    private func beginImport() {
        guard proAccess.hasPro else {
            showingProUpgrade = true
            return
        }
        showingImporter = true
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }
            importRows = try TransactionImportService.parse(data: Data(contentsOf: url))
            showingImportPreview = true
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    private func importRowsIntoStore() {
        for row in importRows {
            let group = row.groupName.flatMap { name in
                budgetGroups.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            } ?? selectedGroup
            let budget = row.budgetName.flatMap { name in
                budgets.first {
                    $0.name.caseInsensitiveCompare(name) == .orderedSame
                        && (group == nil || $0.group === group)
                }
            }
            let transaction = Transaction(
                title: row.title,
                amount: row.amount,
                date: row.date,
                note: row.note,
                type: row.type,
                budget: budget,
                group: group
            )
            do {
                try TransactionRoundUpService.applyIfNeeded(
                    to: transaction,
                    group: group,
                    savingsGoals: savingsGoals,
                    contributions: savingsContributions,
                    modelContext: modelContext
                )
            } catch {
                importErrorMessage = "Die importierten Buchungen konnten nicht aufgerundet werden."
                return
            }
            modelContext.insert(transaction)
        }

        do {
            try modelContext.save()
            importRows = []
            showingImportPreview = false
        } catch {
            importErrorMessage = "Die Buchungen konnten nicht gespeichert werden."
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
                    ForEach(group.transactions, id: \.persistentModelID) { transaction in
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
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
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
                                if $0.createdAt == $1.createdAt {
                                    return $0.id.uuidString > $1.id.uuidString
                                }
                                return $0.createdAt > $1.createdAt
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
        let groupID = transaction.effectiveGroup?.id
        var deletedContributionIDs = Set<UUID>()
        let linkedContributionIDs = [
            transaction.savingsContributionID,
            transaction.roundUpSavingsContributionID
        ].compactMap { $0 }
        if !linkedContributionIDs.isEmpty {
            do {
                let contributions = try modelContext.fetch(FetchDescriptor<SavingsContribution>())
                for contribution in contributions where linkedContributionIDs.contains(contribution.id) {
                    deletedContributionIDs.insert(contribution.id)
                    modelContext.delete(contribution)
                }
            } catch {
                AppLogger.persistence.error(
                    "Zugehöriger Sparbeitrag konnte nicht geladen werden: \(error)"
                )
            }
        }
        modelContext.delete(transaction)

        do {
            try modelContext.save()
            if let groupID {
                for deletedContributionID in deletedContributionIDs {
                    CloudKitSharedAreaService.recordDeletion(
                        key: deletedContributionID.uuidString,
                        kind: .contribution,
                        groupID: groupID
                    )
                }
                CloudKitSharedAreaService.recordDeletion(
                    key: transaction.id.uuidString,
                    kind: .transaction,
                    groupID: groupID
                )
            }
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

private struct ExportFile: Identifiable {
    let url: URL
    var id: URL { url }
}

// MARK: - Tagesgruppe

private struct TransactionDayGroup {
    let date: Date
    let transactions: [Transaction]
}
