import SwiftData
import SwiftUI
import os

private struct SavingsEditorRequest: Identifiable {
    let id = UUID()
    let goal: SavingsGoal?
    let type: SavingsGoalType
    let group: BudgetGroup?
}

struct SavingsView: View {
    @Binding private var addRequested: Bool
    @Binding private var reserveRequested: Bool
    @Binding private var managementRequested: Bool
    @Binding private var archiveRequested: Bool
    @Binding private var selectedDate: Date
    @Binding private var selectedGroup: BudgetGroup?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCurrencyCode) private var currencyCode

    @Query(
        filter: #Predicate<SavingsGoal> { !$0.isArchived },
        sort: [
            SortDescriptor<SavingsGoal>(\.sortOrder),
            SortDescriptor<SavingsGoal>(\.createdAt)
        ]
    )
    private var goals: [SavingsGoal]

    @Query(filter: #Predicate<SavingsGoal> { $0.isArchived })
    private var archivedGoals: [SavingsGoal]

    @Query(
        filter: #Predicate<Budget> { !$0.isArchived },
        sort: [
            SortDescriptor<Budget>(\.sortOrder),
            SortDescriptor<Budget>(\.createdAt)
        ]
    )
    private var budgets: [Budget]

    @State private var savingsEditorRequest: SavingsEditorRequest?
    @State private var showingManagement = false
    @State private var showingArchived = false
    @State private var contributingGoal: SavingsGoal?
    @State private var detailGoal: SavingsGoal?
    @State private var goalToArchive: SavingsGoal?
    @State private var goalToDelete: SavingsGoal?
    @State private var saveErrorMessage: String?

    init(
        addRequested: Binding<Bool> = .constant(false),
        reserveRequested: Binding<Bool> = .constant(false),
        managementRequested: Binding<Bool> = .constant(false),
        archiveRequested: Binding<Bool> = .constant(false),
        selectedDate: Binding<Date> = .constant(.now),
        selectedGroup: Binding<BudgetGroup?> = .constant(nil)
    ) {
        _addRequested = addRequested
        _reserveRequested = reserveRequested
        _managementRequested = managementRequested
        _archiveRequested = archiveRequested
        _selectedDate = selectedDate
        _selectedGroup = selectedGroup
    }

    private var selectedMonthEnd: Date {
        let calendar = Calendar.autoupdatingCurrent
        let interval = calendar.dateInterval(of: .month, for: selectedDate)
        return interval?.end.addingTimeInterval(-1) ?? selectedDate
    }

    private var groupedGoals: [SavingsGoal] {
        guard let selectedGroup else { return goals }
        return goals.filter { $0.group === selectedGroup }
    }

    private var visibleGoals: [SavingsGoal] {
        groupedGoals.filter { $0.createdAt <= selectedMonthEnd }
    }

    private var visibleArchivedGoals: [SavingsGoal] {
        guard let selectedGroup else { return archivedGoals }
        return archivedGoals.filter { $0.group === selectedGroup }
    }

    private var visibleBudgets: [Budget] {
        guard let selectedGroup else { return budgets }
        return budgets.filter { $0.group === selectedGroup }
    }

    var body: some View {
        Group {
            if visibleGoals.isEmpty {
                emptyState
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                content
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.3), value: visibleGoals.isEmpty)
        .sheet(item: $savingsEditorRequest) { request in
            if request.type == .goal {
                SavingsGoalEditorView(goal: request.goal, budgets: visibleBudgets, type: .goal, group: request.group)
            } else {
                FreeReserveEditorView(reserve: request.goal, budgets: visibleBudgets, group: request.group)
            }
        }
        .sheet(isPresented: $showingManagement) {
            SavingsManagementView(goals: groupedGoals, archivedGoals: visibleArchivedGoals, budgets: visibleBudgets)
        }
        .sheet(isPresented: $showingArchived) {
            ArchivedSavingsView(goals: visibleArchivedGoals)
        }
        .sheet(item: $contributingGoal) { goal in
            SavingsContributionEditorView(goal: goal, budgets: visibleBudgets)
        }
        .sheet(item: $detailGoal) { goal in
            SavingsGoalDetailView(
                goal: goal,
                currencyCode: currencyCode,
                onEdit: {
                    detailGoal = nil
                    savingsEditorRequest = SavingsEditorRequest(
                        goal: goal,
                        type: goal.type,
                        group: selectedGroup
                    )
                },
                onContribute: {
                    detailGoal = nil
                    contributingGoal = goal
                }
            )
        }
        .alert(
            "In den Archiv verschieben?",
            isPresented: archiveConfirmationIsPresented,
            presenting: goalToArchive
        ) { goal in
            Button("Archivieren") { archive(goal) }
            Button("Abbrechen", role: .cancel) { goalToArchive = nil }
        } message: { goal in
            Text("„\(goal.name)“ bleibt erhalten und kann später im Archiv wiederhergestellt werden.")
        }
        .alert(
            "Sparziel löschen?",
            isPresented: deleteConfirmationIsPresented,
            presenting: goalToDelete
        ) { goal in
            Button("Löschen", role: .destructive) { delete(goal) }
            Button("Abbrechen", role: .cancel) { goalToDelete = nil }
        } message: { goal in
            Text("„\(goal.name)“ und seine Einzahlungen werden dauerhaft gelöscht.")
        }
        .saveErrorAlert(message: $saveErrorMessage)
        .task {
            migrateLegacyGoals()
        }
        .onChange(of: addRequested) { _, requested in
            guard requested else { return }
            openEditor(for: .goal)
            addRequested = false
        }
        .onChange(of: reserveRequested) { _, requested in
            guard requested else { return }
            openEditor(for: .reserve)
            reserveRequested = false
        }
        .onChange(of: managementRequested) { _, requested in
            guard requested else { return }
            showingManagement = true
            managementRequested = false
        }
        .onChange(of: archiveRequested) { _, requested in
            guard requested else { return }
            showingArchived = true
            archiveRequested = false
        }
    }

    private var content: some View {
        List {
            let activeGoals = visibleGoals.filter { $0.type == .goal }
            let reserves = visibleGoals.filter { $0.type == .reserve }

            if !activeGoals.isEmpty {
                Section("Sparziele") { }
                ForEach(activeGoals) { goal in
                    Section { goalRow(goal) }
                }
            }
            if !reserves.isEmpty {
                Section("Freie Rücklagen") { }
                ForEach(reserves) { goal in
                    Section { goalRow(goal) }
                }
            }
            if visibleGoals.isEmpty {
                Section {
                    Text("Noch keine aktiven Sparziele oder freien Rücklagen.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        #else
        .listStyle(.inset)
        #endif
    }

    @ViewBuilder
    private func goalRow(_ goal: SavingsGoal) -> some View {
        SavingsGoalCardView(
            goal: goal,
            currencyCode: currencyCode,
            asOf: selectedMonthEnd,
            contribute: { contributingGoal = goal }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            detailGoal = goal
        }
        .contextMenu {
            Button {
                savingsEditorRequest = SavingsEditorRequest(
                    goal: goal,
                    type: goal.type,
                    group: selectedGroup
                )
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }

            Button {
                goalToArchive = goal
            } label: {
                Label("Archivieren", systemImage: "archivebox")
            }

            Divider()

            Button(role: .destructive) {
                goalToDelete = goal
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .swipeActions {
            Button {
                goalToArchive = goal
            } label: {
                Label("Archivieren", systemImage: "archivebox")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Noch keine Sparziele", systemImage: "banknote")
        } description: {
            Text("Lege Sparziele oder freie Rücklagen an und behalte deine Fortschritte im Blick.")
        } actions: {
            Menu("Hinzufügen") {
                Button("Neues Sparziel") { openEditor(for: .goal) }
                Button("Neue freie Rücklage") { openEditor(for: .reserve) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var archiveConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { goalToArchive != nil },
            set: { if !$0 { goalToArchive = nil } }
        )
    }

    private var deleteConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { goalToDelete != nil },
            set: { if !$0 { goalToDelete = nil } }
        )
    }

    private func moveGoals(from source: IndexSet, to destination: Int) {
        var reordered = goals
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, goal) in reordered.enumerated() {
            goal.sortOrder = index
            goal.updatedAt = .now
        }
        do { try modelContext.save() }
        catch { saveErrorMessage = error.localizedDescription }
    }

    private func openEditor(for type: SavingsGoalType) {
        savingsEditorRequest = SavingsEditorRequest(
            goal: nil,
            type: type,
            group: selectedGroup
        )
    }

    private func migrateLegacyGoals() {
        let legacyGoals = goals.filter { $0.type == .goal && $0.targetAmount == nil }
        guard !legacyGoals.isEmpty else { return }

        for goal in legacyGoals {
            goal.type = .reserve
            goal.updatedAt = .now
        }
        do {
            try modelContext.save()
        } catch {
            AppLogger.persistence.error("Legacy-Sparziele konnten nicht migriert werden: \(error.localizedDescription)")
        }
    }

    private func archive(_ goal: SavingsGoal) {
        goal.isArchived = true
        goal.updatedAt = .now
        do { try modelContext.save() }
        catch { saveErrorMessage = error.localizedDescription }
        goalToArchive = nil
    }

    private func delete(_ goal: SavingsGoal) {
        let groupID = goal.group?.id
        let contributionIDs = (goal.contributions ?? []).map(\.id)
        modelContext.delete(goal)
        do {
            try modelContext.save()
            if let groupID {
                CloudKitSharedAreaService.recordDeletion(
                    key: goal.id.uuidString,
                    kind: .savingsGoal,
                    groupID: groupID
                )
                for contributionID in contributionIDs {
                    CloudKitSharedAreaService.recordDeletion(
                        key: contributionID.uuidString,
                        kind: .contribution,
                        groupID: groupID
                    )
                }
            }
        }
        catch { saveErrorMessage = error.localizedDescription }
        goalToDelete = nil
    }
}

private struct SavingsManagementView: View {
    let goals: [SavingsGoal]
    let archivedGoals: [SavingsGoal]
    let budgets: [Budget]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var savingsEditorRequest: SavingsEditorRequest?
    @State private var showingArchived = false
    @State private var goalToDelete: SavingsGoal?
    @State private var saveErrorMessage: String?

    private var activeGoals: [SavingsGoal] {
        goals.filter { $0.type == .goal }
    }

    private var activeReserves: [SavingsGoal] {
        goals.filter { $0.type == .reserve }
    }

    var body: some View {
        NavigationStack {
            List {
                if !activeGoals.isEmpty {
                    Section {
                        ForEach(activeGoals) { goal in
                            managementRow(for: goal)
                        }
                        .onMove { source, destination in
                            move(source, to: destination, within: activeGoals)
                        }
                    } header: {
                        Text("Sparziele")
                    }
                }

                if !activeReserves.isEmpty {
                    Section {
                        ForEach(activeReserves) { goal in
                            managementRow(for: goal)
                        }
                        .onMove { source, destination in
                            move(source, to: destination, within: activeReserves)
                        }
                    } header: {
                        Text("Freie Rücklagen")
                    }
                }

                if goals.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "Keine aktiven Einträge",
                            systemImage: "arrow.up.arrow.down",
                            description: Text("Lege zuerst ein Sparziel oder eine freie Rücklage an.")
                        )
                    }
                }

                Section {
                    Button("Archiv öffnen") { showingArchived = true }
                }
            }
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            #endif
            .navigationTitle("Verwalten")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .alert(
                "Sparziel löschen?",
                isPresented: deleteConfirmationIsPresented,
                presenting: goalToDelete
            ) { goal in
                Button("Löschen", role: .destructive) { delete(goal) }
                Button("Abbrechen", role: .cancel) { goalToDelete = nil }
            } message: { goal in
                Text("„\(goal.name)“ und seine Einzahlungen werden dauerhaft gelöscht.")
            }
            .saveErrorAlert(message: $saveErrorMessage)
            .sheet(item: $savingsEditorRequest) { request in
                if request.type == .goal {
                    SavingsGoalEditorView(goal: request.goal, budgets: budgets, type: .goal, group: request.group)
                } else {
                    FreeReserveEditorView(reserve: request.goal, budgets: budgets, group: request.group)
                }
            }
            .sheet(isPresented: $showingArchived) {
                ArchivedSavingsView(goals: archivedGoals)
            }
        }
    }

    private var deleteConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { goalToDelete != nil },
            set: { if !$0 { goalToDelete = nil } }
        )
    }

    @ViewBuilder
    private func managementRow(for goal: SavingsGoal) -> some View {
        HStack(spacing: 12) {
            IconBadgeView(
                iconName: goal.iconName,
                color: Color(hexString: goal.iconColorHex),
                size: 38
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(goal.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(goal.type.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button {
                    savingsEditorRequest = SavingsEditorRequest(
                        goal: goal,
                        type: goal.type,
                        group: goal.group
                    )
                } label: {
                    Label("Bearbeiten", systemImage: "pencil")
                }
                Button { archive(goal) } label: {
                    Label("Archivieren", systemImage: "archivebox")
                }
                Divider()
                Button(role: .destructive) { goalToDelete = goal } label: {
                    Label("Löschen", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .menuOrder(.fixed)
        }
    }

    private func move(
        _ source: IndexSet,
        to destination: Int,
        within items: [SavingsGoal]
    ) {
        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, goal) in reordered.enumerated() {
            goal.sortOrder = index
            goal.updatedAt = .now
        }

        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func archive(_ goal: SavingsGoal) {
        goal.isArchived = true
        goal.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func delete(_ goal: SavingsGoal) {
        let groupID = goal.group?.id
        let contributionIDs = (goal.contributions ?? []).map(\.id)
        modelContext.delete(goal)
        do {
            try modelContext.save()
            if let groupID {
                CloudKitSharedAreaService.recordDeletion(
                    key: goal.id.uuidString,
                    kind: .savingsGoal,
                    groupID: groupID
                )
                for contributionID in contributionIDs {
                    CloudKitSharedAreaService.recordDeletion(
                        key: contributionID.uuidString,
                        kind: .contribution,
                        groupID: groupID
                    )
                }
            }
        } catch {
            saveErrorMessage = error.localizedDescription
        }
        goalToDelete = nil
    }
}

private struct ArchivedSavingsView: View {
    let goals: [SavingsGoal]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var goalToDelete: SavingsGoal?
    @State private var saveErrorMessage: String?

    var body: some View {
        NavigationStack {
            List(goals) { goal in
                HStack {
                    IconBadgeView(
                        iconName: goal.iconName,
                        color: Color(hexString: goal.iconColorHex),
                        size: 36
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(goal.name)
                            .lineLimit(1)
                        Text(goal.type == .goal ? "Sparziel" : "Freie Rücklage")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button {
                            restore(goal)
                        } label: {
                            Label("Wiederherstellen", systemImage: "arrow.uturn.backward")
                        }
                        Divider()
                        Button(role: .destructive) {
                            goalToDelete = goal
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .imageScale(.large)
                    }
                }
            }
            .navigationTitle("Archiv")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .alert(
                "Archivierten Eintrag löschen?",
                isPresented: deleteConfirmationIsPresented,
                presenting: goalToDelete
            ) { goal in
                Button("Löschen", role: .destructive) { delete(goal) }
                Button("Abbrechen", role: .cancel) { goalToDelete = nil }
            } message: { goal in
                Text("„\(goal.name)“ und seine Einzahlungen werden dauerhaft gelöscht.")
            }
            .saveErrorAlert(message: $saveErrorMessage)
        }
    }

    private var deleteConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { goalToDelete != nil },
            set: { if !$0 { goalToDelete = nil } }
        )
    }

    private func restore(_ goal: SavingsGoal) {
        goal.isArchived = false
        goal.updatedAt = .now
        saveChanges()
    }

    private func delete(_ goal: SavingsGoal) {
        let groupID = goal.group?.id
        let contributionIDs = (goal.contributions ?? []).map(\.id)
        modelContext.delete(goal)
        if saveChanges(), let groupID {
            CloudKitSharedAreaService.recordDeletion(
                key: goal.id.uuidString,
                kind: .savingsGoal,
                groupID: groupID
            )
            for contributionID in contributionIDs {
                CloudKitSharedAreaService.recordDeletion(
                    key: contributionID.uuidString,
                    kind: .contribution,
                    groupID: groupID
                )
            }
        }
        goalToDelete = nil
    }

    @discardableResult
    private func saveChanges() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            saveErrorMessage = error.localizedDescription
            return false
        }
    }
}

private struct SavingsGoalDetailView: View {
    let goal: SavingsGoal
    let currencyCode: String
    let onEdit: () -> Void
    let onContribute: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ProAccessManager.self) private var proAccess
    @State private var showingProUpgrade = false

    private var savedAmount: Decimal {
        goal.savedAmount
    }

    private var contributions: [SavingsContribution] {
        (goal.contributions ?? []).sorted { $0.date > $1.date }
    }

    private var progress: Double {
        guard let target = goal.targetAmount, target > 0 else { return 0 }
        return min(max(NSDecimalNumber(decimal: savedAmount / target).doubleValue, 0), 1)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Übersicht") {
                    LabeledContent("Gespart") {
                        Text(savedAmount, format: .currency(code: currencyCode))
                            .font(.headline)
                    }

                    if let target = goal.targetAmount, target > 0 {
                        LabeledContent("Zielbetrag") {
                            Text(target, format: .currency(code: currencyCode))
                        }
                        if let targetDate = goal.targetDate {
                            LabeledContent("Zieldatum") {
                                Text(targetDate, format: .dateTime.day().month().year())
                            }
                        }
                        LabeledContent("Verbleibend") {
                            Text(max(target - savedAmount, .zero), format: .currency(code: currencyCode))
                        }
                        ProgressView(value: progress)
                            .tint(progress >= 1 ? .green : .accentColor)
                    } else {
                        Text("Freie Rücklage ohne festen Zielbetrag")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Prognose") {
                    if proAccess.hasPro {
                        let forecast = SavingsGoalForecast.calculate(for: goal)

                        if let monthlyRate = forecast.monthlyRate {
                            LabeledContent("Monatlicher Sparbetrag") {
                                Text(monthlyRate, format: .currency(code: currencyCode))
                            }
                        }

                        if let requiredMonthlyAmount = forecast.requiredMonthlyAmount,
                           requiredMonthlyAmount > 0 {
                            LabeledContent("Benötigt bis zum Zieldatum") {
                                Text(requiredMonthlyAmount, format: .currency(code: currencyCode))
                            }
                        }

                        if let completionDate = forecast.estimatedCompletionDate {
                            LabeledContent("Voraussichtlich erreicht") {
                                Text(completionDate, format: .dateTime.month(.wide).year())
                            }
                        }

                        if let explanation = forecast.explanation {
                            Label(explanation, systemImage: forecast.isOnTrack == false ? "exclamationmark.triangle" : "info.circle")
                                .font(.footnote)
                                .foregroundStyle(forecast.isOnTrack == false ? .orange : .secondary)
                        }
                    } else {
                        Button {
                            showingProUpgrade = true
                        } label: {
                            Label("Detaillierte Sparprognosen sind in Pro verfügbar.", systemImage: "lock.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Verlauf") {
                    if contributions.isEmpty {
                        ContentUnavailableView(
                            "Noch keine Einzahlungen",
                            systemImage: "tray",
                            description: Text("Füge die erste Einzahlung für dieses \(goal.type == .goal ? "Sparziel" : "Rücklage") hinzu.")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(contributions, id: \.persistentModelID) { contribution in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(contribution.date, format: .dateTime.day().month().year())
                                        .font(.headline)
                                    Text(contribution.amount >= 0
                                        ? (contribution.automatic ? "Automatische Einzahlung" : "Manuelle Einzahlung")
                                        : "Auszahlung")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !contribution.note.isEmpty {
                                        Text(contribution.note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(contribution.amount, format: .currency(code: currencyCode))
                                    .font(.headline)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingProUpgrade) {
                ProUpgradeView(feature: "Detaillierte Sparprognosen")
            }
            .navigationTitle(goal.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Einzahlen", action: onContribute)
                        Button("Bearbeiten", action: onEdit)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}

private struct SavingsGoalCardView: View {
    let goal: SavingsGoal
    let currencyCode: String
    let asOf: Date
    let contribute: () -> Void

    private var savedAmount: Decimal {
        goal.savedAmount(asOf: asOf)
    }

    private var historicalProgress: Double {
        guard let target = goal.targetAmount, target > 0 else { return 0 }
        return min(max(NSDecimalNumber(decimal: savedAmount / target).doubleValue, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconBadgeView(
                    iconName: goal.iconName,
                    color: Color(hexString: goal.iconColorHex),
                    size: 46
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.name)
                        .font(.headline)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 3) {
                    Text(savedAmount, format: .currency(code: currencyCode))
                        .font(.headline)
                    if let target = goal.targetAmount, target > 0 {
                        Text("von \(target, format: .currency(code: currencyCode))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if goal.type == .goal {
                ProgressView(value: historicalProgress)
                    .tint(historicalProgress >= 1 ? .green : .accentColor)

                if let targetDate = goal.targetDate {
                    Text("Ziel bis \(targetDate, format: .dateTime.day().month().year())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                if goal.automaticBooking {
                    Label("Automatisch \(goal.frequency.title.lowercased())", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Manuelle Einzahlung", systemImage: "hand.tap")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let budget = goal.budget {
                    Label(budget.name, systemImage: budget.iconName)
                        .font(.caption)
                        .foregroundStyle(Color(hexString: budget.iconColorHex))
                }

                Spacer()

                Button("Einzahlen", action: contribute)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 5)
    }

}

#Preview {
    SavingsView()
        .modelContainer(for: [UserSettings.self, BudgetGroup.self, BudgetGroupMonthlyAllocation.self, Budget.self, Transaction.self, FixedCost.self, SavingsGoal.self, SavingsContribution.self], inMemory: true)
}
