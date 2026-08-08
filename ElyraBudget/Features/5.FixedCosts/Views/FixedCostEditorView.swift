import SwiftData
import SwiftUI

struct FixedCostEditorView: View {
    let fixedCost: FixedCost?
    let budgets: [Budget]
    let group: BudgetGroup?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor<Transaction>(\.date)])
    private var transactions: [Transaction]

    @State private var title: String
    @State private var amount: Decimal?
    @State private var frequency: FixedCostFrequency
    @State private var schedule: FixedCostSchedule
    @State private var anchorDate: Date
    @State private var automaticBooking: Bool
    @State private var isPaused: Bool
    @State private var pauseUntil: Date
    @State private var note: String
    @State private var selectedBudget: Budget?
    @State private var showingBudgetMenu = false
    @State private var showingSavingsGoalEditor = false
    @State private var saveErrorMessage: String?

    init(fixedCost: FixedCost?, budgets: [Budget], group: BudgetGroup? = nil) {
        self.fixedCost = fixedCost
        self.budgets = budgets
        self.group = group ?? fixedCost?.group
        _title = State(initialValue: fixedCost?.title ?? "")
        _amount = State(initialValue: fixedCost?.amount)
        _frequency = State(initialValue: fixedCost?.frequency ?? .monthly)
        _schedule = State(initialValue: fixedCost?.schedule ?? .fixedDay)
        _anchorDate = State(initialValue: fixedCost?.anchorDate ?? .now)
        _automaticBooking = State(initialValue: fixedCost?.automaticBooking ?? true)
        _isPaused = State(initialValue: fixedCost?.isPaused ?? false)
        _pauseUntil = State(initialValue: fixedCost?.pauseUntil ?? .now)
        _note = State(initialValue: fixedCost?.note ?? "")
        _selectedBudget = State(initialValue: fixedCost?.budget)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                    Section("Grunddaten") {
                        VStack(spacing: 0) {
                            TextField("Bezeichnung", text: $title)
                                .padding(.horizontal, 17)
                                .frame(minHeight: 56)

                            Divider()
                                .padding(.horizontal, 17)

                            FixedCostEditorAmountSection(
                                amount: $amount
                            )
                        }
                        .background(cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }

                    Section("Intervall") {
                        Picker("Häufigkeit", selection: $frequency) {
                            ForEach(FixedCostFrequency.allCases) { Text($0.title).tag($0) }
                        }
                        if frequency.months != nil {
                            Picker("Abbuchung", selection: $schedule) {
                                ForEach(FixedCostSchedule.allCases) { Text($0.title).tag($0) }
                            }
                        }
                        DatePicker("Startdatum", selection: $anchorDate, displayedComponents: .date)
                    }

                    Section("Zuordnung") {
                        HStack(spacing: 12) {
                            Text("Budget")
                            Spacer(minLength: 8)
                            Button {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    showingBudgetMenu.toggle()
                                }
                            } label: {
                                selectedBudgetValue
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(showingBudgetMenu ? Color.accentColor : Color.secondary.opacity(0.55))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Section("Buchung") {
                        Toggle("Automatisch buchen", isOn: $automaticBooking)
                        TextField("Notiz (optional)", text: $note, axis: .vertical)
                    }

                    if fixedCost != nil {
                        Section {
                            Button {
                                showingSavingsGoalEditor = true
                            } label: {
                                Label(
                                    hasLinkedSavingsGoal ? "Sparziel bearbeiten" : "Sparziel anlegen",
                                    systemImage: "banknote"
                                )
                            }
                            .disabled(hasLinkedSavingsGoal)
                        } header: {
                            Text("Sparen")
                        } footer: {
                            Text("Aus dieser Fixkostenposition wird ein vorausgefülltes Sparziel erstellt.")
                        }
                    }

                    Section("Pause") {
                        Toggle("Fixkosten pausieren", isOn: $isPaused)
                        if isPaused {
                            DatePicker("Pausiert bis", selection: $pauseUntil, displayedComponents: .date)
                            Text("Nach diesem Datum wird die Fixkostenbuchung wieder fällig.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }

                if showingBudgetMenu {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture { closeBudgetMenu() }
                        .zIndex(1)

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            TransactionEditorBudgetMenu(
                                budgets: budgets,
                                selectedBudget: $selectedBudget,
                                isPresented: $showingBudgetMenu
                            )
                            .padding(.trailing, 25)
                            .padding(.bottom, 300)
                        }
                    }
                    .zIndex(2)
                }
            }
            .navigationTitle(fixedCost == nil ? "Neue Fixkosten" : "Fixkosten bearbeiten")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || amount == nil)
                }
            }
            .saveErrorAlert(message: $saveErrorMessage)
            .sheet(isPresented: $showingSavingsGoalEditor) {
                SavingsGoalEditorView(
                    goal: nil,
                    budgets: budgets,
                    type: .goal,
                    group: group,
                    linkedFixedCost: fixedCost
                )
            }
        }
    }

    private var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color.secondary.opacity(0.08)
        #endif
    }

    private var hasLinkedSavingsGoal: Bool {
        fixedCost?.savingsGoals?.contains { !$0.isArchived } == true
    }

    private func save() {
        guard let amount else { return }
        guard BudgetGroupRelationshipValidator.isValid(budget: selectedBudget, in: group) else {
            saveErrorMessage = "Das ausgewählte Budget gehört zu einem anderen Budgetbereich."
            return
        }
        let value = fixedCost ?? FixedCost()
        value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.amount = abs(amount)
        value.frequency = frequency
        value.schedule = schedule
        value.anchorDate = Calendar.autoupdatingCurrent.startOfDay(for: anchorDate)
        value.dayOfMonth = min(
            max(Calendar.autoupdatingCurrent.component(.day, from: anchorDate), 1),
            31
        )
        value.automaticBooking = automaticBooking
        value.isPaused = isPaused
        value.pauseUntil = isPaused ? Calendar.autoupdatingCurrent.startOfDay(for: pauseUntil) : nil
        value.note = note
        value.budget = selectedBudget
        value.group = group ?? selectedBudget?.group
        value.updatedAt = .now
        if fixedCost == nil { modelContext.insert(value) }
        do {
            try modelContext.save()

            if value.automaticBooking {
                try FixedCostScheduler.processAutomaticBookings(
                    fixedCosts: [value],
                    transactions: transactions,
                    modelContext: modelContext
                )
            }

            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private var selectedBudgetValue: some View {
        if let selectedBudget {
            HStack(spacing: 7) {
                Image(systemName: selectedBudget.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hexString: selectedBudget.iconColorHex))
                Text(selectedBudget.name)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            Text("Kein Budget")
                .foregroundStyle(.tint)
                .lineLimit(1)
        }
    }

    private func closeBudgetMenu() {
        withAnimation(.easeInOut(duration: 0.16)) {
            showingBudgetMenu = false
        }
    }

}
