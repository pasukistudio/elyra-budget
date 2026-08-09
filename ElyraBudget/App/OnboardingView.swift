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
                ProgressView(value: Double(step + 1), total: 3)
                    .tint(.accentColor)
                    .padding(.horizontal)
                    .padding(.top, 12)

                TabView(selection: $step) {
                    welcomePage.tag(0)
                    profilePage.tag(1)
                    templatesPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 12) {
                    if step > 0 {
                        Button("Zurück") { step -= 1 }
                            .buttonStyle(.bordered)
                    }

                    Spacer()

                    Button(step == 2 ? "Starten" : "Weiter") {
                        if step == 2 {
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
            Text("Du kannst alles später in den Einstellungen ändern.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
                    }
                    .buttonStyle(.plain)
                }

                Button("Überspringen") {
                    selectedTemplates.removeAll()
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding()
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

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 58, weight: .semibold))
                .foregroundStyle(.tint)
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
