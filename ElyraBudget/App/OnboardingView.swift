








import SwiftData
import SwiftUI
import os

struct OnboardingView: View {
    let group: BudgetGroup?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCurrencyCode) private var currencyCode

    @Query(sort: \UserSettings.updatedAt, order: .reverse)
    private var profiles: [UserSettings]

    @State private var step = 0
    @State private var name = ""
    @State private var monthlyBudgetText = ""
    @State private var selectedTemplates: Set<String> = []
    @State private var selectedSavingsExamples: Set<String> = []
    @State private var selectedFixedCostExamples: Set<String> = []
    @State private var includeExampleTransaction = true
    @State private var saveErrorMessage: String?
    @FocusState private var focusedField: InputField?

    private enum InputField: Hashable {
        case name
        case monthlyBudget
    }

    private static let templates: [BudgetTemplate] = [
        BudgetTemplate(name: "Lebensmittel", iconName: "cart.fill", iconColorHex: "#FF9500", limit: 400),
        BudgetTemplate(name: "Wohnen", iconName: "house.fill", iconColorHex: "#007AFF", limit: 1_000),
        BudgetTemplate(name: "Mobilität", iconName: "car.fill", iconColorHex: "#FF2D55", limit: 250),
        BudgetTemplate(name: "Freizeit", iconName: "gamecontroller.fill", iconColorHex: "#AF52DE", limit: 150),
        BudgetTemplate(name: "Abonnements", iconName: "repeat", iconColorHex: "#34C759", limit: 75)
    ]

    private static let savingsExamples: [StarterExample] = [
        StarterExample(
            id: "notgroschen",
            title: "Notgroschen",
            description: "100 € monatlich für unerwartete Ausgaben",
            iconName: "shield.fill",
            iconColorHex: "#34C759",
            amount: 100
        ),
        StarterExample(
            id: "urlaub",
            title: "Urlaub",
            description: "75 € monatlich für dein nächstes Reiseziel",
            iconName: "airplane.departure",
            iconColorHex: "#007AFF",
            amount: 75
        )
    ]

    private static let fixedCostExamples: [StarterExample] = [
        StarterExample(
            id: "miete",
            title: "Miete",
            description: "850 € monatlich am 1. des Monats",
            iconName: "house.fill",
            iconColorHex: "#5856D6",
            amount: 850
        ),
        StarterExample(
            id: "streaming",
            title: "Streaming",
            description: "15 € monatlich für ein Abonnement",
            iconName: "play.tv.fill",
            iconColorHex: "#FF2D55",
            amount: 15
        )
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: 8)
                    .tint(.accentColor)
                    .padding(.horizontal)
                    .padding(.top, 12)

                HStack(spacing: 7) {
                    ForEach(0 ..< 8, id: \.self) { page in
                        Capsule(style: .continuous)
                            .fill(page == step ? Color.accentColor : Color.secondary.opacity(0.22))
                            .frame(width: page == step ? 20 : 7, height: 7)
                            .animation(.easeInOut(duration: 0.2), value: step)
                    }
                }
                .padding(.top, 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Schritt \(step + 1) von 8")

                TabView(selection: $step) {
                    welcomePage.tag(0)
                    profilePage.tag(1)
                    templatesPage.tag(2)
                    interactionPage.tag(3)
                    savingsPage.tag(4)
                    fixedCostsPage.tag(5)
                    swipeUsagePage.tag(6)
                    longPressUsagePage.tag(7)
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #else
                .tabViewStyle(.automatic)
                #endif
                .animation(.easeInOut(duration: 0.25), value: step)

                HStack(spacing: 12) {
                    if step > 0 {
                        Button("Zurück") { step -= 1 }
                            .buttonStyle(.bordered)
                    }

                    Spacer()

                    Button(step == 7 ? "Los geht's" : "Weiter") {
                        focusedField = nil

                        if step == 7 {
                            finishOnboarding()
                        } else {
                            withAnimation { step += 1 }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(step == 1 && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Willkommen bei Elyra Budget")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .interactiveDismissDisabled()
            .task {
                name = profiles.first?.name ?? ""
                monthlyBudgetText = "1.800"
            }
            .saveErrorAlert(message: $saveErrorMessage)
        }
    }

    private var welcomePage: some View {
        OnboardingPage(
            title: "Deine Finanzen, einfach im Blick",
            systemImage: "chart.pie.fill",
            description: "Elyra Budget hilft dir, Budgets, Buchungen, Fixkosten und Sparziele an einem Ort zu organisieren."
        ) {
            VStack(spacing: 8) {
                onboardingInfoCard(
                    systemImage: "gauge.with.dots.needle.67percent",
                    color: .accentColor,
                    title: "Gesamtbudget",
                    text: "Dein monatlicher Rahmen für alle Ausgaben."
                )
                onboardingInfoCard(
                    systemImage: "square.grid.2x2.fill",
                    color: .blue,
                    title: "Budgets",
                    text: "Teile dein Gesamtbudget auf, zum Beispiel für Lebensmittel oder Freizeit."
                )
                onboardingInfoCard(
                    systemImage: "list.bullet.rectangle",
                    color: .orange,
                    title: "Buchungen",
                    text: "Trage Einnahmen und Ausgaben ein – Elyra zeigt dir, was noch verfügbar ist."
                )
                onboardingInfoCard(
                    systemImage: "calendar.badge.clock",
                    color: .green,
                    title: "Sparen & Fixkosten",
                    text: "Plane regelmäßige Zahlungen und lege Geld für deine Ziele zurück."
                )
            }
        }
    }

    private var profilePage: some View {
        OnboardingPage(
            title: "Wie dürfen wir dich nennen?",
            systemImage: "person.crop.circle",
            description: "Dein Name wird nur für die persönliche Begrüßung in der Übersicht verwendet."
        ) {
            TextField("Dein Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .textContentType(.name)
                .submitLabel(.done)
                .focused($focusedField, equals: .name)
        }
    }

    private var templatesPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                OnboardingPageHeader(
                    title: "Dein Monatsrahmen",
                    systemImage: "square.grid.2x2.fill",
                    description: "Das Gesamtbudget ist dein monatlicher Rahmen. Budgets zeigen dir, wofür du ihn ausgibst."
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Gesamtbudget pro Monat")
                        .font(.headline)
                    TextField("Zum Beispiel 1.800 €", text: $monthlyBudgetText)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .monthlyBudget)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text("Du kannst den Betrag später für jeden Monat anpassen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Beispielbudgets auswählen")
                    .font(.title3.bold())
                    .padding(.top, 4)

                ForEach(Self.templates) { template in
                    Button {
                        if selectedTemplates.contains(template.id) {
                            selectedTemplates.remove(template.id)
                        } else {
                            selectedTemplates.insert(template.id)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            IconBadgeView(
                                iconName: template.iconName,
                                color: Color(hexString: template.iconColorHex),
                                size: 42
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(template.limit, format: .currency(code: currencyCode))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            Spacer()
                            Image(systemName: selectedTemplates.contains(template.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selectedTemplates.contains(template.id) ? Color.accentColor : .secondary)
                        }
                        .padding(12)
                        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    selectedTemplates.contains(template.id) ? Color.accentColor : .clear,
                                    lineWidth: 2
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button("Überspringen") {
                    selectedTemplates.removeAll()
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                Text("Du kannst Budgets, Währung und weitere Einstellungen später jederzeit ändern.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private var interactionPage: some View {
        OnboardingPage(
            title: "Buchungen ausprobieren",
            systemImage: "cart.fill",
            description: "Mit einer Beispielbuchung siehst du direkt, wie Einnahmen und Ausgaben in Elyra Budget funktionieren.",
            content: {
                VStack(spacing: 10) {
                    exampleToggle(
                        isOn: $includeExampleTransaction,
                        systemImage: "cart.fill",
                        color: .orange,
                        title: "Beispielbuchung",
                        text: "Supermarkt · 48,60 €"
                    )

                    Text("Du kannst das Beispiel später jederzeit bearbeiten oder löschen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        )
    }

    private var savingsPage: some View {
        OnboardingPage(
            title: "Sparen planen",
            systemImage: "target",
            description: "Sparziele zeigen dir, wofür du regelmäßig Geld zurücklegst. Wähle ein Beispiel aus oder starte ohne Sparziel.",
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        exampleSelectionSection(
                            title: "Beispiele für Sparziele",
                            description: "Zum Beispiel für einen Notgroschen oder deinen nächsten Urlaub.",
                            examples: Self.savingsExamples,
                            selection: $selectedSavingsExamples
                        )

                        Text("Du kannst Sparziele später jederzeit bearbeiten oder löschen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        )
    }

    private var fixedCostsPage: some View {
        OnboardingPage(
            title: "Fixkosten im Blick behalten",
            systemImage: "calendar.badge.clock",
            description: "Fixkosten werden automatisch in deiner Monatsplanung berücksichtigt. Wähle Beispiele aus, damit du direkt starten kannst.",
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        exampleSelectionSection(
                            title: "Beispiele für Fixkosten",
                            description: "Zum Beispiel Miete oder ein Streaming-Abonnement.",
                            examples: Self.fixedCostExamples,
                            selection: $selectedFixedCostExamples
                        )

                        Text("Du kannst Fixkosten später jederzeit bearbeiten oder löschen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        )
    }

    private var swipeUsagePage: some View {
        OnboardingPage(
            title: "Nach links wischen",
            systemImage: "arrow.left",
            description: "Wische eine Karte nach links, um weitere Inhalte oder Funktionen zu sehen.",
            content: {
                swipeTransactionDemo
                    .padding(.horizontal)
            }
        )
    }

    private var longPressUsagePage: some View {
        OnboardingPage(
            title: "Gedrückt halten",
            systemImage: "hand.tap.fill",
            description: "Halte eine Karte oder einen Eintrag länger gedrückt, um ein Untermenü zu öffnen.",
            content: {
                savingsContextMenuDemo
                    .padding(.horizontal)
            }
        )
    }

    private var swipeTransactionDemo: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 8) {
                swipeActionButton(title: "Bearbeiten", systemImage: "pencil", color: .blue)
                swipeActionButton(title: "Löschen", systemImage: "trash", color: .teal)
            }

            HStack(spacing: 10) {
                Image(systemName: "arrow.up.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(width: 44, height: 44)
                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Supermarkt")
                        .font(.headline)
                    Text("16. Aug. 2026")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text("-48,60 €")
                    .font(.headline)
                    .foregroundStyle(.red)
            }
            .padding(12)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .offset(x: -48)
        }
        .frame(height: 76)
    }

    private var savingsContextMenuDemo: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "bicycle")
                        .foregroundStyle(.green)
                        .frame(width: 44, height: 44)
                        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BMW S1000RR")
                            .font(.headline)
                        Text("0,00 € von 23.000,00 €")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: 5)
                HStack {
                    Label("Manuelle Einzahlung", systemImage: "hand.tap")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Einzahlen")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.teal)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.teal.opacity(0.12), in: Capsule())
                }
            }
            .padding(12)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Label("Bearbeiten", systemImage: "pencil")
                Label("Archivieren", systemImage: "archivebox")
                Divider()
                Label("Löschen", systemImage: "trash")
                    .foregroundStyle(.red)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func swipeActionButton(title: LocalizedStringKey, systemImage: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.caption2)
        }
        .foregroundStyle(.white)
        .frame(width: 48, height: 52)
        .background(color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func interactionHintCard<Demo: View>(
        systemImage: String,
        color: Color,
        title: LocalizedStringKey,
        text: LocalizedStringKey,
        @ViewBuilder demo: () -> Demo
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                    .frame(width: 22)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            demo()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func onboardingInfoCard(
        systemImage: String,
        color: Color,
        title: LocalizedStringKey,
        text: LocalizedStringKey
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func exampleToggle(
        isOn: Binding<Bool>,
        systemImage: String,
        color: Color,
        title: LocalizedStringKey,
        text: LocalizedStringKey
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }
        .toggleStyle(.switch)
        .padding(12)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func exampleSelectionSection(
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        examples: [StarterExample],
        selection: Binding<Set<String>>
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.bold())
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(examples) { example in
                let isSelected = selection.wrappedValue.contains(example.id)
                Button {
                    if isSelected {
                        selection.wrappedValue.remove(example.id)
                    } else {
                        selection.wrappedValue.insert(example.id)
                    }
                } label: {
                    HStack(spacing: 10) {
                        IconBadgeView(
                            iconName: example.iconName,
                            color: Color(hexString: example.iconColorHex),
                            size: 34
                        )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(example.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(example.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 0)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    }
                    .padding(10)
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    private func finishOnboarding() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = profiles.first ?? UserSettings()
        profile.name = trimmedName
        profile.updatedAt = .now
        if profiles.isEmpty {
            modelContext.insert(profile)
        }

        let targetGroup = group ?? fetchOrCreateDefaultGroup()
        if let monthlyBudgetAmount {
            targetGroup.standardMonthlyBudget = monthlyBudgetAmount
            targetGroup.updatedAt = .now
        }

        let existingNames = Set((targetGroup.budgets ?? []).map { $0.name.localizedLowercase })
        var availableBudgets = targetGroup.budgets ?? []
        for template in Self.templates where selectedTemplates.contains(template.id) {
            guard !existingNames.contains(template.name.localizedLowercase) else { continue }
            let budget = Budget(
                name: template.name,
                iconName: template.iconName,
                iconColorHex: template.iconColorHex,
                limit: template.limit,
                group: targetGroup
            )
            modelContext.insert(budget)
            availableBudgets.append(budget)
        }

        if includeExampleTransaction {
            let supermarketBudget = availableBudgets.first {
                $0.name.localizedCaseInsensitiveCompare("Lebensmittel") == .orderedSame
            }
            let existingExample = (targetGroup.transactions ?? []).contains {
                $0.title.localizedCaseInsensitiveCompare("Supermarkt") == .orderedSame
            }
            if !existingExample {
                modelContext.insert(
                    Transaction(
                        title: "Supermarkt",
                        amount: 48.60,
                        date: .now,
                        note: "Beispielbuchung zum Ausprobieren",
                        budget: supermarketBudget,
                        group: targetGroup
                    )
                )
            }
        }

        let existingSavingsNames = Set((targetGroup.savingsGoals ?? []).map { $0.name.localizedLowercase })
        for example in Self.savingsExamples where selectedSavingsExamples.contains(example.id) {
            guard !existingSavingsNames.contains(example.title.localizedLowercase) else { continue }
            let target: Decimal = example.id == "notgroschen" ? 3_000 : 1_200
            modelContext.insert(
                SavingsGoal(
                    name: example.title,
                    type: .goal,
                    targetAmount: target,
                    contributionAmount: example.amount,
                    frequency: .monthly,
                    anchorDate: .now,
                    group: targetGroup
                )
            )
        }

        let existingFixedCostNames = Set((targetGroup.fixedCosts ?? []).map { $0.title.localizedLowercase })
        for example in Self.fixedCostExamples where selectedFixedCostExamples.contains(example.id) {
            guard !existingFixedCostNames.contains(example.title.localizedLowercase) else { continue }
            modelContext.insert(
                FixedCost(
                    title: example.title,
                    amount: example.amount,
                    frequency: .monthly,
                    schedule: .firstDayOfMonth,
                    anchorDate: .now,
                    dayOfMonth: 1,
                    group: targetGroup
                )
            )
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private var monthlyBudgetAmount: Decimal? {
        let normalized = monthlyBudgetText
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Decimal(string: normalized, locale: Locale(identifier: "en_US"))
    }

    private func fetchOrCreateDefaultGroup() -> BudgetGroup {
        do {
            if let existing = try modelContext.fetch(FetchDescriptor<BudgetGroup>())
                .first(where: { !$0.isArchived }) {
                return existing
            }
        } catch {
            AppLogger.persistence.error(
                "Standard-Budgetbereich konnte im Onboarding nicht geladen werden: \(error)"
            )
        }

        let created = BudgetGroup(name: "Persönlich", iconName: "person.fill")
        modelContext.insert(created)
        return created
    }
}

private struct BudgetTemplate: Identifiable {
    let name: String
    let iconName: String
    let iconColorHex: String
    let limit: Decimal

    var id: String { name }
}

private struct StarterExample: Identifiable {
    let id: String
    let title: String
    let description: String
    let iconName: String
    let iconColorHex: String
    let amount: Decimal
}

private struct OnboardingPage<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: LocalizedStringKey
    @ViewBuilder let content: () -> Content

    init(
        title: LocalizedStringKey,
        systemImage: String,
        description: LocalizedStringKey,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.content = content
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            hero
            .frame(width: 104, height: 104)
            .shadow(color: .accentColor.opacity(0.25), radius: 18, y: 8)
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
            content()
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding()
    }

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.accentColor, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

private struct OnboardingPageHeader: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.title2.bold())
            Text(description)
                .foregroundStyle(.secondary)
        }
    }

}

#Preview("Onboarding") {
    OnboardingView(group: nil)
        .environment(
            \.appCurrencyCode,
            AppCurrency.eur.rawValue
        )
        .modelContainer(
            for: [
                UserSettings.self,
                BudgetGroup.self,
                Budget.self
            ],
            inMemory: true
        )
}
