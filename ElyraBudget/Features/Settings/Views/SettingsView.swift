import SwiftData
import OSLog
import SwiftUI

struct SettingsView: View {
    @Environment(ProAccessManager.self) private var proAccess
    @Environment(CloudKitSyncMonitor.self) private var cloudKitSyncMonitor
    @Environment(\.modelContext) private var modelContext

    @State private var draftName = ""
    @State private var showingProUpgrade = false
    @State private var proUpgradeFeature = "Mehr Funktionen"
    @State private var saveErrorMessage: String?

    @Query(
        sort: \UserSettings.updatedAt,
        order: .reverse
    )
    private var profiles: [UserSettings]

    private let columns = [
        GridItem(.adaptive(minimum: 72), spacing: 12)
    ]

    var body: some View {
        Form {
            profileSection
            appearanceSection
            currencySection
            budgetStatusSection
            accentColorSection
            proSection
            supportSection
            cloudKitSyncSection

            #if DEBUG
                developerSection
            #endif
        }
        .navigationTitle("Einstellungen")

        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif

            .task {
                createProfileIfNeeded()
            }
            .onChange(
                of: profiles.first?.updatedAt,
                initial: true
            ) {
                loadDraftName()
            }
            .onDisappear {
                saveName()
            }
            .saveErrorAlert(message: $saveErrorMessage)
            .sheet(isPresented: $showingProUpgrade) {
                ProUpgradeView(feature: proUpgradeFeature)
            }
    }

    // MARK: - iCloud

    private var supportSection: some View {
        Section("Hilfe & Feedback") {
            NavigationLink {
                FeedbackView()
            } label: {
                Label("Feedback & Roadmap", systemImage: "bubble.left.and.bubble.right.fill")
            }
        }
    }

    private var cloudKitSyncSection: some View {
        Section("iCloud-Synchronisierung") {
            HStack(spacing: 12) {
                Label(
                    cloudKitSyncMonitor.status.title,
                    systemImage: cloudKitSyncMonitor.status.systemImage
                )
                Spacer()
                if cloudKitSyncMonitor.status == .syncing {
                    ProgressView()
                }
            }

            if let lastSyncDate = cloudKitSyncMonitor.lastSyncDate {
                LabeledContent("Zuletzt aktualisiert") {
                    Text(lastSyncDate, format: .dateTime.day().month().year().hour().minute())
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage = cloudKitSyncMonitor.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                Button("Fehler ausblenden") {
                    cloudKitSyncMonitor.clearError()
                }
            }
        }
    }

    // MARK: - Währung

    private var currencySection: some View {
        Section("Währung") {
            if let profile = profiles.first {
                Picker(
                    "Hauptwährung",
                    selection: Binding(
                        get: {
                            AppCurrency(rawValue: profile.currencyRawValue)
                                ?? .eur
                        },
                        set: { currency in
                            profile.currencyRawValue = currency.rawValue
                            profile.updatedAt = .now
                            saveSettings()
                        }
                    )
                ) {
                    ForEach(AppCurrency.allCases) { currency in
                        Text(currency.title).tag(currency)
                    }
                }
            }
        }
    }

    // MARK: - Budgetstatus

    private var budgetStatusSection: some View {
        Section {
            if let profile = profiles.first {
                Stepper {
                    LabeledContent("Grün bis") {
                        Text("\(profile.greenBudgetThreshold) %")
                            .foregroundStyle(.green)
                    }
                } onIncrement: {
                    profile.greenBudgetThreshold = min(
                        profile.greenBudgetThreshold + 1,
                        profile.orangeBudgetThreshold - 1
                    )
                    saveSettings()
                } onDecrement: {
                    profile.greenBudgetThreshold = max(
                        profile.greenBudgetThreshold - 1,
                        1
                    )
                    saveSettings()
                }

                Stepper {
                    LabeledContent("Orange bis") {
                        Text("\(profile.orangeBudgetThreshold) %")
                            .foregroundStyle(.orange)
                    }
                } onIncrement: {
                    profile.orangeBudgetThreshold += 1
                    saveSettings()
                } onDecrement: {
                    profile.orangeBudgetThreshold = max(
                        profile.orangeBudgetThreshold - 1,
                        profile.greenBudgetThreshold + 1
                    )
                    saveSettings()
                }

                LabeledContent("Rot ab") {
                    Text("\(profile.orangeBudgetThreshold + 1) %")
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Budgetstatus")
        } footer: {
            Text("Die Farben zeigen, wie viel des Monatsbudgets bereits verwendet wurde.")
        }
    }

    // MARK: - Profil

    @ViewBuilder
    private var profileSection: some View {
        Section("Profil") {
            if profiles.first != nil {
                TextField(
                    "Dein Name",
                    text: $draftName
                )
                .textContentType(.name)

                #if os(iOS)
                    .submitLabel(.done)
                #endif

                    .onSubmit {
                        saveName()
                    }
            } else {
                ProgressView()
            }
        }
    }

    // MARK: - Erscheinungsbild

    @ViewBuilder
    private var appearanceSection: some View {
        Section("Darstellung") {
            if let profile = profiles.first {
                Picker(
                    "Erscheinungsbild",
                    selection: Binding(
                        get: {
                            AppAppearance(
                                rawValue: profile.appearanceRawValue
                            ) ?? .system
                        },
                        set: { appearance in
                            profile.appearanceRawValue =
                                appearance.rawValue

                            profile.updatedAt = Date()
                            saveSettings()
                        }
                    )
                ) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Label(
                            appearance.title,
                            systemImage: appearance.icon
                        )
                        .tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - Akzentfarbe

    @ViewBuilder
    private var accentColorSection: some View {
        Section {
            if let profile = profiles.first {
                LazyVGrid(
                    columns: columns,
                    spacing: 16
                ) {
                    ForEach(freeAccentColors) { accentColor in
                        accentColorButton(
                            accentColor,
                            profile: profile
                        )
                    }
                }
                .padding(.vertical, 8)

                customColorRow(profile: profile)
            }
        } header: {
            Text("Akzentfarbe")
        } footer: {
            Text(
                "Eine eigene Akzentfarbe ist Bestandteil von Elyra Budget Pro."
            )
        }
    }

    private var freeAccentColors: [AppAccentColor] {
        AppAccentColor.allCases.filter {
            !$0.isProOnly
        }
    }

    private func accentColorButton(
        _ accentColor: AppAccentColor,
        profile: UserSettings
    ) -> some View {
        let isSelected =
            profile.accentColorRawValue ==
            accentColor.rawValue

        return Button {
            withAnimation {
                profile.accentColorRawValue =
                    accentColor.rawValue

                if let preset = accentColor.preset {
                    profile.customAccentHex =
                        preset.hex
                }

                profile.updatedAt = Date()
                saveSettings()
            }
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(
                            previewColor(
                                for: accentColor
                            )
                        )
                        .frame(
                            width: 38,
                            height: 38
                        )

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.headline)
                            .foregroundStyle(
                                checkmarkColor(
                                    for: accentColor
                                )
                            )
                    }
                }

                Text(accentColor.title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text(accentColor.title)
        )
        .accessibilityAddTraits(
            isSelected ? .isSelected : []
        )
    }

    @ViewBuilder
    private func customColorRow(
        profile: UserSettings
    ) -> some View {
        if proAccess.hasPro {
            ColorPicker(
                selection: Binding(
                    get: {
                        Color(
                            hexString: profile.customAccentHex
                        )
                    },
                    set: { newColor in
                        guard let hex = newColor.toHex() else {
                            return
                        }

                        guard profile.customAccentHex != hex else {
                            return
                        }

                        profile.customAccentHex = hex
                        profile.accentColorRawValue =
                            AppAccentColor.custom.rawValue
                        profile.updatedAt = Date()

                        saveSettings()
                    }
                ),
                supportsOpacity: false
            ) {
                Label(
                    "Eigene Farbe",
                    systemImage: "paintpalette"
                )
            }
        } else {
            Button {
                proUpgradeFeature = "Eigene Akzentfarben"
                showingProUpgrade = true
            } label: {
                HStack {
                    Label(
                        "Eigene Farbe",
                        systemImage: "paintpalette"
                    )

                    Spacer()

                    Text("PRO")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            .tint.opacity(0.15),
                            in: Capsule()
                        )

                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func previewColor(
        for accentColor: AppAccentColor
    ) -> Color {
        accentColor.color ?? .accentColor
    }

    private func checkmarkColor(
        for accentColor: AppAccentColor
    ) -> Color {
        switch accentColor {
        case .orange, .pink:
            return .black

        default:
            return .white
        }
    }

    // MARK: - Pro

    private var proSection: some View {
        Section("Elyra Budget Pro") {
            Button {
                proUpgradeFeature = "Mehr Funktionen"
                showingProUpgrade = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: proAccess.hasPro ? "checkmark.seal.fill" : "sparkles")
                        .foregroundStyle(proAccess.hasPro ? .green : .accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(proAccess.hasPro ? "Pro ist freigeschaltet" : "Pro entdecken")
                            .foregroundStyle(.primary)
                        Text(
                            proAccess.hasPro
                                ? "Alle verfügbaren Pro-Funktionen sind aktiv."
                                : "Mehr Kontrolle, tiefere Einblicke und eigene Gestaltung."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !proAccess.hasPro {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Entwicklung

    #if DEBUG
        private var developerSection: some View {
            Section("Entwicklung") {
                Toggle(
                    "Pro zum Testen aktivieren",
                    isOn: Binding(
                        get: {
                            proAccess.hasPro
                        },
                        set: { newValue in
                            proAccess.hasPro = newValue
                        }
                    )
                )
            }
        }
    #endif

    // MARK: - Namensverwaltung

    private func loadDraftName() {
        guard let profile = profiles.first else {
            return
        }

        draftName = profile.name
    }

    private func saveName() {
        guard let profile = profiles.first else {
            return
        }

        let cleanedName = draftName
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard profile.name != cleanedName else {
            return
        }

        profile.name = cleanedName
        profile.updatedAt = Date()

        saveSettings()
    }

    // MARK: - SwiftData

    private func createProfileIfNeeded() {
        guard profiles.isEmpty else {
            return
        }

        let profile = UserSettings()
        modelContext.insert(profile)

        saveSettings()
    }

    private func saveSettings() {
        guard modelContext.hasChanges else {
            return
        }

        do {
            try modelContext.save()
        } catch {
            AppLogger.persistence.error(
                "UserSettings konnten nicht gespeichert werden: \(error)"
            )
            saveErrorMessage = "Die Einstellungen konnten nicht gespeichert werden."
        }
    }

}

#Preview("Free") {
    NavigationStack {
        SettingsView()
    }
    .environment(ProAccessManager())
    .environment(CloudKitSyncMonitor(environment: ["ELYRA_BUDGET_USE_CLOUDKIT": "NO"]))
    .modelContainer(
        for: UserSettings.self,
        inMemory: true
    )
}

#Preview("Pro") {
    let proAccess = ProAccessManager()
    proAccess.hasPro = true

    return NavigationStack {
        SettingsView()
    }
    .environment(proAccess)
    .environment(CloudKitSyncMonitor(environment: ["ELYRA_BUDGET_USE_CLOUDKIT": "NO"]))
    .modelContainer(
        for: UserSettings.self,
        inMemory: true
    )
}
