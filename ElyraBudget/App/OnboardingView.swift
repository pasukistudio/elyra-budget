import SwiftData
import SwiftUI

struct OnboardingView: View {
    let group: BudgetGroup?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCurrencyCode) private var currencyCode

    @Query(sort: \UserSettings.updatedAt, order: .reverse)
    private var profiles: [UserSettings]

    @State private var step = 0
    @State private var name = ""
    @State private var selectedTemplates: Set<String> = []
    @State private var saveErrorMessage: String?
    @State private var tutorialGestureOffset: CGFloat = -6
    @State private var showingProUpgrade = false

    private static let templates: [BudgetTemplate] = [
        BudgetTemplate(name: "Lebensmittel", iconName: "cart.fill", iconColorHex: "#FF9500", limit: 400),
        BudgetTemplate(name: "Wohnen", iconName: "house.fill", iconColorHex: "#007AFF", limit: 1_000),
        BudgetTemplate(name: "Mobilität", iconName: "car.fill", iconColorHex: "#FF2D55", limit: 250),
        BudgetTemplate(name: "Freizeit", iconName: "gamecontroller.fill", iconColorHex: "#AF52DE", limit: 150),
        BudgetTemplate(name: "Abonnements", iconName: "repeat", iconColorHex: "#34C759", limit: 75)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: 4)
                    .tint(.accentColor)
                    .padding(.horizontal)
                    .padding(.top, 12)

                HStack(spacing: 7) {
                    ForEach(0 ..< 4, id: \.self) { page in
                        Capsule(style: .continuous)
                            .fill(page == step ? Color.accentColor : Color.secondary.opacity(0.22))
                            .frame(width: page == step ? 20 : 7, height: 7)
                            .animation(.easeInOut(duration: 0.2), value: step)
                    }
                }
                .padding(.top, 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Schritt \(step + 1) von 4")

                TabView(selection: $step) {
                    welcomePage.tag(0)
                    profilePage.tag(1)
                    templatesPage.tag(2)
                    interactionPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: step)

                HStack(spacing: 12) {
                    if step > 0 {
                        Button("Zurück") { step -= 1 }
                            .buttonStyle(.bordered)
                    }

                    Spacer()

                    Button(step == 3 ? "Los geht's" : "Weiter") {
                        if step == 3 {
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
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Einfach starten, jederzeit anpassen")
                }
                HStack(spacing: 10) {
                    Image(systemName: "icloud.fill")
                        .foregroundStyle(.blue)
                    Text("Deine Daten bleiben auf deinen Geräten synchron")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        }
    }

    private var templatesPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                OnboardingPageHeader(
                    title: "Mit Vorlagen starten",
                    systemImage: "square.grid.2x2.fill",
                    description: "Wähle häufige Budgets aus. Du kannst sie später bearbeiten oder löschen."
                )

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
            title: "Alles Wichtige auf einen Blick",
            systemImage: "hand.draw.fill",
            description: "Mit kleinen Gesten erreichst du die wichtigsten Funktionen deiner Karten.",
            content: {
                VStack(spacing: 14) {
                    tutorialCard(
                        systemImage: "arrow.left.and.right",
                        color: .accentColor,
                        title: "Nach links wischen",
                        message: "Zeigt schnelle Aktionen wie Archivieren oder Löschen."
                    )

                    tutorialCard(
                        systemImage: "hand.tap.fill",
                        color: .orange,
                        title: "Gedrückt halten",
                        message: "Öffnet weitere Optionen wie Bearbeiten und Verwalten."
                    )

                    HStack(spacing: 10) {
                        Image(systemName: "hand.point.right.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                            .offset(x: tutorialGestureOffset)
                            .animation(
                                .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                                value: tutorialGestureOffset
                            )
                        Text("Du kannst jederzeit zurückkommen und alles ändern.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)

                    Button {
                        showingProUpgrade = true
                    } label: {
                        Label("Pro kennenlernen", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .padding(.top, 4)
                }
                .onAppear { tutorialGestureOffset = 6 }
            }
        )
        .sheet(isPresented: $showingProUpgrade) {
            ProUpgradeView(feature: "Detaillierte Prognosen")
        }
    }

    private func tutorialCard(
        systemImage: String,
        color: Color,
        title: LocalizedStringKey,
        message: LocalizedStringKey
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        let existingNames = Set((targetGroup.budgets ?? []).map { $0.name.localizedLowercase })
        for template in Self.templates where selectedTemplates.contains(template.id) {
            guard !existingNames.contains(template.name.localizedLowercase) else { continue }
            modelContext.insert(
                Budget(
                    name: template.name,
                    iconName: template.iconName,
                    iconColorHex: template.iconColorHex,
                    limit: template.limit,
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

    private func fetchOrCreateDefaultGroup() -> BudgetGroup {
        if let existing = (try? modelContext.fetch(FetchDescriptor<BudgetGroup>()))?
            .first(where: { !$0.isArchived }) {
            return existing
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
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            content()
                .frame(maxWidth: 320)
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
