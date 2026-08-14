import SwiftData
import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(ProAccessManager.self) private var proAccess
    @Environment(CloudKitSyncMonitor.self) private var cloudKitSyncMonitor
    @Environment(\.modelContext) private var modelContext

    @State private var draftName = ""
    @State private var showingProUpgrade = false
    @State private var proUpgradeFeature = "Mehr Funktionen"
    @State private var saveErrorMessage: String?
    @State private var showingBackupExporter = false
    @State private var backupDocument: ElyraBudgetBackupDocument?
    @State private var showingBackupImporter = false
    @State private var pendingBackupData: Data?
    @State private var showingImportConfirmation = false

    @Query(
        sort: \UserSettings.updatedAt,
        order: .reverse
    )
    private var profiles: [UserSettings]

    var body: some View {
        Form {
            profileSection
            appearanceSection
            currencySection
            budgetStatusSection
            securitySection
            notificationsSection
            accentColorSection
            proSection
            supportSection
            cloudKitSyncSection
            dataTransferSection
            legalSection
            aboutSection

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
            .fileExporter(
                isPresented: $showingBackupExporter,
                document: backupDocument,
                contentType: .json,
                defaultFilename: "ElyraBudget-Backup"
            ) { result in
                if case .failure(let error) = result {
                    saveErrorMessage = "Die Sicherung konnte nicht exportiert werden: \(error.localizedDescription)"
                }
            }
            .fileImporter(
                isPresented: $showingBackupImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleBackupImportSelection(result)
            }
            .confirmationDialog(
                "Backup importieren?",
                isPresented: $showingImportConfirmation,
                titleVisibility: .visible
            ) {
                Button("Bestehende Daten ersetzen", role: .destructive) {
                    importPendingBackup()
                }
                Button("Abbrechen", role: .cancel) {
                    pendingBackupData = nil
                }
            } message: {
                Text("Die lokalen Daten dieser App werden durch die Sicherung ersetzt. Dieser Schritt kann nicht rückgängig gemacht werden.")
            }
    }

    // MARK: - iCloud

    private var supportSection: some View {
        Section("Hilfe & Support") {
            Link(destination: URL(string: "mailto:support@pasukistudio.de?subject=Elyra%20Budget%20Support")!) {
                Label("Support per E-Mail", systemImage: "envelope.fill")
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

    private var dataTransferSection: some View {
        Section("Daten übertragen") {
            Button {
                prepareBackupExport()
            } label: {
                Label("Backup exportieren", systemImage: "square.and.arrow.up")
            }

            Button {
                showingBackupImporter = true
            } label: {
                Label("Backup importieren", systemImage: "square.and.arrow.down")
            }

            Text("Übertrage deine Daten lokal zwischen App-Versionen. Belege werden mitgesichert.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var aboutSection: some View {
        Section("Über Elyra Budget") {
            LabeledContent("Version") {
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }

            Link(destination: URL(string: "https://github.com/pasukistudio/elyra-budget")!) {
                Label("Projekt auf GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }

            Link(destination: URL(string: "https://github.com/pasukistudio/elyra-budget/issues")!) {
                Label("Fehler auf GitHub melden", systemImage: "ladybug")
            }
        }
    }

    private var legalSection: some View {
        Section("Rechtliches") {
            Link(destination: URL(string: "https://pasukistudio.de/datenschutz/")!) {
                Label("Datenschutz", systemImage: "hand.raised.fill")
            }

            Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                Label("Nutzungsbedingungen (EULA)", systemImage: "doc.text.fill")
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        return "\(version) (Build \(build))"
    }

    private var notificationsSection: some View {
        Section("Benachrichtigungen") {
            NavigationLink {
                NotificationSettingsView(
                    profile: profiles.first,
                    saveSettings: saveSettings,
                    requestPermission: requestNotificationPermissionIfNeeded(for:)
                )
            } label: {
                HStack(spacing: 12) {
                    Label("Benachrichtigungen", systemImage: "bell.badge.fill")
                    Spacer()
                    Text(notificationSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var notificationSummary: String {
        guard let profile = profiles.first else { return "Wird geladen …" }

        let enabledCount = [
            profile.budgetNotificationsEnabled,
            profile.savingsContributionNotificationsEnabled,
            profile.syncErrorNotificationsEnabled,
            profile.savingsGoalCompletionNotificationsEnabled,
            profile.automaticBookingFailureNotificationsEnabled,
            profile.monthlySummaryNotificationsEnabled,
            profile.forecastRiskNotificationsEnabled,
            profile.overdueFixedCostNotificationsEnabled,
            profile.syncRecoveryNotificationsEnabled,
            profile.unusualExpenseNotificationsEnabled,
            profile.dailyDigestNotificationsEnabled
        ].filter { $0 }.count

        return enabledCount == 0 ? "Aus" : "\(enabledCount) aktiv"
    }

    private var securitySection: some View {
        Section("Sicherheit") {
            if let profile = profiles.first, proAccess.hasPro {
                Toggle(
                    "Face ID-/Touch-ID-Sperre",
                    isOn: Binding(
                        get: { profile.appLockEnabled },
                        set: {
                            profile.appLockEnabled = $0
                            profile.updatedAt = .now
                            saveSettings()
                        }
                    )
                )
                Text("Elyra Budget wird beim Verlassen der App geschützt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    proUpgradeFeature = "Face ID-/Touch-ID-Sperre"
                    showingProUpgrade = true
                } label: {
                    Label("Face ID-/Touch-ID-Sperre mit Pro", systemImage: "faceid")
                }
            }
        }
    }

    private func requestNotificationPermissionIfNeeded(for isEnabled: Bool) {
        guard isEnabled else { return }
        Task {
            _ = await FixedCostNotificationScheduler.requestAuthorizationIfNeeded()
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
                customColorRow(profile: profile)
            }
        } header: {
            Text("Akzentfarbe")
        } footer: {
            Text(
                "Eigene Farben sind Bestandteil von Elyra Budget Pro."
            )
        }
    }

    private func customColorRow(
        profile: UserSettings
    ) -> some View {
        PresetColorSelectionView(
            selection: Binding(
                get: { profile.customAccentHex },
                set: { profile.customAccentHex = $0 }
            ),
            title: "Akzentfarbe"
        ) { hex in
            profile.customAccentHex = hex
            profile.accentColorRawValue = AppAccentColor.custom.rawValue
            profile.updatedAt = .now
            saveSettings()
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
                            if newValue {
                                proAccess.enableProForTesting()
                            } else {
                                proAccess.disableProForTesting()
                            }
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

    private func prepareBackupExport() {
        do {
            backupDocument = ElyraBudgetBackupDocument(
                data: try ElyraBudgetBackupService.exportData(from: modelContext)
            )
            showingBackupExporter = true
        } catch {
            saveErrorMessage = "Die Sicherung konnte nicht erstellt werden: \(error.localizedDescription)"
        }
    }

    private func handleBackupImportSelection(
        _ result: Result<[URL], Error>
    ) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            pendingBackupData = try Data(contentsOf: url)
            showingImportConfirmation = true
        } catch {
            saveErrorMessage = "Die Sicherung konnte nicht gelesen werden: \(error.localizedDescription)"
        }
    }

    private func importPendingBackup() {
        guard let pendingBackupData else { return }
        do {
            try ElyraBudgetBackupService.importData(
                pendingBackupData,
                into: modelContext
            )
            self.pendingBackupData = nil
        } catch {
            saveErrorMessage = error.localizedDescription
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
