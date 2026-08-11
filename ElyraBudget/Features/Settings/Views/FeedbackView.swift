import Foundation
import Combine
import SwiftData
import SwiftUI
import Auth
import PostgREST
import Supabase

private enum FeedbackConfiguration {
    static let supportEmail = "support@pasukistudio.de"
}

private enum FeedbackKind: String, Codable, CaseIterable, Identifiable {
    case feature
    case bug

    var id: Self { self }

    var title: String {
        switch self {
        case .feature: "Feature-Wunsch"
        case .bug: "Fehlerbericht"
        }
    }

    var icon: String {
        switch self {
        case .feature: "lightbulb.fill"
        case .bug: "ladybug.fill"
        }
    }

    var tint: Color {
        switch self {
        case .feature: .orange
        case .bug: .red
        }
    }
}

private enum FeedbackState: String, Codable {
    case planned
    case inProgress = "in_progress"
    case completed
    case underReview = "under_review"

    var title: String {
        switch self {
        case .planned: "Geplant"
        case .inProgress: "In Arbeit"
        case .completed: "Umgesetzt"
        case .underReview: "In Prüfung"
        }
    }

    var tint: Color {
        switch self {
        case .planned: .blue
        case .inProgress: .orange
        case .completed: .green
        case .underReview: .purple
        }
    }

}

private struct FeedbackPost: Codable, Identifiable, Hashable {
    let id: String
    let kind: FeedbackKind
    let title: String
    let detail: String
    let state: FeedbackState
    let voteCount: Int
    let hasVoted: Bool
    let createdAt: Date

    var isBuiltInRoadmapItem: Bool {
        id.hasPrefix("roadmap-")
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind = "type"
        case title
        case detail
        case state
        case voteCount
        case hasVoted
        case createdAt
    }
}

private struct SupabaseFeedbackRecord: Decodable {
    let id: String
    let kind: String
    let title: String
    let detail: String
    let status: String
    let voteCount: Int
    let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case detail
        case status
        case voteCount = "vote_count"
        case createdAt = "created_at"
    }
}

private struct SupabaseFeedbackInsert: Encodable {
    let id: UUID
    let kind: String
    let title: String
    let detail: String
}

private struct SupabaseVoteRecord: Decodable {
    let postID: String

    private enum CodingKeys: String, CodingKey {
        case postID = "post_id"
    }
}

@MainActor
private final class FeedbackService: ObservableObject {
    @Published private(set) var posts: [FeedbackPost] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    var feedbackNotificationsEnabled = true

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let userID = try await ensureAnonymousUserID()
            let records: [SupabaseFeedbackRecord] = try await SupabaseService.client
                .from("feedback_posts")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value

            let votes: [SupabaseVoteRecord] = try await SupabaseService.client
                .from("feedback_votes")
                .select("post_id")
                .eq("user_id", value: userID.uuidString)
                .execute()
                .value

            let votedPostIDs = Set(votes.map(\.postID))
            let loadedPosts = records.map { record in
                FeedbackPost(
                    id: record.id,
                    kind: FeedbackKind(rawValue: record.kind) ?? .feature,
                    title: record.title,
                    detail: record.detail,
                    state: FeedbackState(rawValue: record.status) ?? .underReview,
                    voteCount: record.voteCount,
                    hasVoted: votedPostIDs.contains(record.id),
                    createdAt: ISO8601DateFormatter().date(from: record.createdAt) ?? .now
                )
            }
            for post in loadedPosts where UserDefaults.standard.bool(forKey: submittedKey(for: post.id)) {
                let statusKey = statusKey(for: post.id)
                if let previousStatus = UserDefaults.standard.string(forKey: statusKey),
                   previousStatus != post.state.rawValue {
                    Task {
                        await AppNotificationScheduler.scheduleFeedbackStatusChange(
                            title: post.title,
                            state: post.state.title,
                            enabled: feedbackNotificationsEnabled,
                            postID: post.id
                        )
                    }
                }
                UserDefaults.standard.set(post.state.rawValue, forKey: statusKey)
            }
            posts = loadedPosts
            errorMessage = nil
        } catch {
            errorMessage = "Feedback konnte gerade nicht geladen werden. Bitte prüfe deine Internetverbindung und versuche es erneut."
        }
    }

    func submit(
        kind: FeedbackKind,
        title: String,
        detail: String,
        notifyOnUpdates: Bool
    ) async throws {
        _ = try await ensureAnonymousUserID()
        if notifyOnUpdates {
            _ = await FixedCostNotificationScheduler.requestAuthorizationIfNeeded()
        }
        let postID = UUID()
        try await SupabaseService.client
            .from("feedback_posts")
            .insert(SupabaseFeedbackInsert(
                id: postID,
                kind: kind.rawValue,
                title: title,
                detail: detail
            ))
            .execute()
        // New submissions are intentionally hidden until approved, so the insert
        // response cannot be read back under the public RLS policy. Persist the
        // client-generated ID so status notifications still work after approval.
        UserDefaults.standard.set(notifyOnUpdates, forKey: submittedKey(for: postID.uuidString))
        UserDefaults.standard.set(FeedbackState.underReview.rawValue, forKey: statusKey(for: postID.uuidString))
        await load()
    }

    private func submittedKey(for postID: String) -> String {
        "elyraBudget.feedback.submitted.\(postID)"
    }

    private func statusKey(for postID: String) -> String {
        "elyraBudget.feedback.status.\(postID)"
    }

    func toggleVote(for post: FeedbackPost) async throws {
        let userID = try await ensureAnonymousUserID()
        if post.hasVoted {
            try await SupabaseService.client
                .from("feedback_votes")
                .delete()
                .eq("post_id", value: post.id)
                .eq("user_id", value: userID.uuidString)
                .execute()
        } else {
            try await SupabaseService.client
                .from("feedback_votes")
                .insert(SupabaseVoteInsert(postID: post.id, userID: userID.uuidString))
                .execute()
        }
        await load()
    }

    private func ensureAnonymousUserID() async throws -> UUID {
        if let session = SupabaseService.client.auth.currentSession {
            return session.user.id
        }
        let session = try await SupabaseService.client.auth.signInAnonymously()
        return session.user.id
    }
}

private struct SupabaseVoteInsert: Encodable {
    let postID: String
    let userID: String

    private enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case userID = "user_id"
    }
}

struct FeedbackView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case roadmap
        case features
        case bugs

        var id: Self { self }

        var title: String {
            switch self {
            case .roadmap: "Roadmap"
            case .features: "Features"
            case .bugs: "Fehler"
            }
        }
    }

    @Environment(\.openURL) private var openURL
    @Query private var userSettings: [UserSettings]
    @StateObject private var service = FeedbackService()
    @State private var filter: Filter = .roadmap
    @State private var composerKind: FeedbackKind = .feature
    @State private var showingComposer = false
    @State private var votingPostIDs: Set<String> = []
    @State private var voteErrorMessage: String?

    private var visiblePosts: [FeedbackPost] {
        switch filter {
        case .roadmap:
            service.posts.filter { post in
                post.state == .planned || post.state == .inProgress
            } + plannedRoadmapPosts.filter { roadmapItem in
                !service.posts.contains(where: { $0.id == roadmapItem.id })
            }
        case .features:
            service.posts.filter { $0.kind == .feature }
        case .bugs:
            service.posts.filter { $0.kind == .bug }
        }
    }

    private var plannedRoadmapPosts: [FeedbackPost] {
        [
            FeedbackPost(
                id: "roadmap-ipados-layout",
                kind: .feature,
                title: "Optimierte iPadOS-Version",
                detail: "Ein großzügiges iPad-Layout mit besserer Nutzung von Split View, Querformat und größeren Bildschirmen.",
                state: .planned,
                voteCount: 0,
                hasVoted: false,
                createdAt: .distantFuture
            ),
            FeedbackPost(
                id: "roadmap-macos-app",
                kind: .feature,
                title: "Elyra Budget für macOS",
                detail: "Eine eigene Mac-App mit optimierter Navigation, Tastaturbedienung und gemeinsamer iCloud-Datenbasis.",
                state: .planned,
                voteCount: 0,
                hasVoted: false,
                createdAt: .distantFuture
            ),
            FeedbackPost(
                id: "roadmap-receipt-recognition",
                kind: .feature,
                title: "Buchungen aus Belegen erfassen",
                detail: "Rechnungen und Belege fotografieren, wichtige Daten automatisch erkennen und als Buchung vorschlagen lassen.",
                state: .planned,
                voteCount: 0,
                hasVoted: false,
                createdAt: .distantFuture
            ),
            FeedbackPost(
                id: "roadmap-forecasts",
                kind: .feature,
                title: "Intelligentere Prognosen",
                detail: "Frühzeitig erkennen, wie sich Budgets, Sparziele und wiederkehrende Kosten in den kommenden Monaten entwickeln.",
                state: .planned,
                voteCount: 0,
                hasVoted: false,
                createdAt: .distantFuture
            )
        ]
    }

    private var emptyStateIcon: String {
        switch filter {
        case .roadmap: "map"
        case .features: "lightbulb"
        case .bugs: "ladybug"
        }
    }

    private var emptyStateTitle: String {
        filter == .roadmap ? "Aktuell nichts geplant" : "Noch keine Beiträge"
    }

    private var emptyStateMessage: String {
        filter == .roadmap
            ? "Sobald neue Arbeiten geplant sind, erscheinen sie hier."
            : "Sei die erste Person mit einem Vorschlag."
    }

    var body: some View {
        List {
            Section {
                Label {
                    Text("Teile Ideen, melde Fehler und stimme direkt in der App ab.")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .foregroundStyle(.tint)
                }
            }

            Section {
                Picker("Ansicht", selection: $filter) {
                    ForEach(Filter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }

            if service.isLoading && service.posts.isEmpty {
                Section {
                    ProgressView("Feedback wird geladen …")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else if let errorMessage = service.errorMessage, service.posts.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            Text(errorMessage)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Erneut laden") {
                            Task { await service.load() }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            } else if visiblePosts.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: emptyStateIcon)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(emptyStateTitle)
                            .font(.headline)
                        Text(emptyStateMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
            } else {
                Section(filter == .roadmap ? "Geplante Arbeiten" : filter.title) {
                    ForEach(visiblePosts) { post in
                        FeedbackPostRow(
                            post: post,
                            onVote: {
                                Task { await toggleVote(for: post) }
                            },
                            isVoting: votingPostIDs.contains(post.id)
                        )
                    }
                }
            }

            Section("Privater Support") {
                Button {
                    if let url = supportEmailURL {
                        openURL(url)
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Support per E-Mail")
                                .font(.headline)
                            Text(FeedbackConfiguration.supportEmail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(.tint)
                            .frame(width: 28)
                    }
                }
            }
        }
        .navigationTitle("Feedback & Roadmap")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        composerKind = .feature
                        showingComposer = true
                    } label: {
                        Label("Feature vorschlagen", systemImage: FeedbackKind.feature.icon)
                    }

                    Button {
                        composerKind = .bug
                        showingComposer = true
                    } label: {
                        Label("Fehler melden", systemImage: FeedbackKind.bug.icon)
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Feedback hinzufügen")
            }
        }
        .task {
            service.feedbackNotificationsEnabled = userSettings.first?.feedbackStatusNotificationsEnabled ?? true
            await service.load()
        }
        .refreshable { await service.load() }
        .alert("Abstimmung nicht gespeichert", isPresented: Binding(
            get: { voteErrorMessage != nil },
            set: { if !$0 { voteErrorMessage = nil } }
        )) {
            Button("OK") { voteErrorMessage = nil }
        } message: {
            Text(voteErrorMessage ?? "Bitte versuche es später erneut.")
        }
        .sheet(isPresented: $showingComposer) {
            FeedbackComposerView(kind: composerKind) { kind, title, detail, notifyOnUpdates in
                try await service.submit(
                    kind: kind,
                    title: title,
                    detail: detail,
                    notifyOnUpdates: notifyOnUpdates
                )
            }
        }
    }

    private func toggleVote(for post: FeedbackPost) async {
        guard !votingPostIDs.contains(post.id) else { return }
        votingPostIDs.insert(post.id)
        defer { votingPostIDs.remove(post.id) }

        do {
            try await service.toggleVote(for: post)
        } catch {
            voteErrorMessage = "Bitte prüfe deine Internetverbindung und versuche es erneut."
        }
    }

    private var supportEmailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = FeedbackConfiguration.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "ElyraBudget Support"),
            URLQueryItem(name: "body", value: "Hallo Pascal,\n\nBeschreibung:\n\n\(diagnostics)")
        ]
        return components.url
    }

    private var diagnostics: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unbekannt"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unbekannt"
        return "- App-Version: \(version) (\(build))\n- System: \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }
}

private struct FeedbackPostRow: View {
    let post: FeedbackPost
    let onVote: () -> Void
    let isVoting: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: post.kind.icon)
                .foregroundStyle(post.kind.tint)
                .frame(width: 28, height: 28)
                .background(post.kind.tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(post.title)
                    .font(.headline)
                Text(post.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                HStack(spacing: 8) {
                    Text(post.state.title)
                        .font(.caption)
                        .foregroundStyle(post.state.tint)
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text(post.kind.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            Button(action: onVote) {
                VStack(spacing: 2) {
                    Image(systemName: post.hasVoted ? "hand.thumbsup.fill" : "hand.thumbsup")
                    Text("\(post.voteCount)")
                        .font(.caption)
                }
                .foregroundStyle(post.hasVoted ? Color.accentColor : .secondary)
                .frame(minWidth: 36)
            }
            .buttonStyle(.plain)
            .disabled(isVoting || post.isBuiltInRoadmapItem)
            .accessibilityLabel(post.hasVoted ? "Stimme entfernen" : "Für Beitrag abstimmen")
            .accessibilityValue(isVoting ? "Wird gespeichert" : "\(post.voteCount) Stimmen")
        }
        .padding(.vertical, 4)
    }
}

private struct FeedbackComposerView: View {
    let kind: FeedbackKind
    let onSubmit: (FeedbackKind, String, String, Bool) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var detail = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showingSubmissionConfirmation = false
    @State private var notifyOnUpdates = false

    private let minimumTitleLength = 3
    private let maximumTitleLength = 120
    private let minimumDetailLength = 3
    private let maximumDetailLength = 5_000

    private var cleanedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cleanedDetail: String {
        detail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        cleanedTitle.count >= minimumTitleLength &&
        cleanedTitle.count <= maximumTitleLength &&
        cleanedDetail.count >= minimumDetailLength &&
        cleanedDetail.count <= maximumDetailLength &&
        !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(kind.title, systemImage: kind.icon)
                        .foregroundStyle(kind.tint)
                }

                Section {
                    TextField("Kurzer Titel", text: $title)
                    TextEditor(text: $detail)
                        .frame(minHeight: 130)
                        .overlay(alignment: .topLeading) {
                            if detail.isEmpty {
                                Text(kind == .bug ? "Was ist passiert?" : "Was würdest du dir wünschen?")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("Dein Beitrag")
                } footer: {
                    Text("Titel: 3–120 Zeichen · Beschreibung: 3–5.000 Zeichen")
                }

                Section("Rückmeldung") {
                    Toggle("Über Statusänderungen informieren", isOn: $notifyOnUpdates)
                    Text("Du erhältst eine Mitteilung, sobald dein Beitrag geprüft, geplant oder umgesetzt wurde.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(kind.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Senden") {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit)
                }
            }
            .overlay {
                if isSubmitting {
                    ProgressView()
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .alert("Danke für deinen Beitrag", isPresented: $showingSubmissionConfirmation) {
                Button("Fertig") { dismiss() }
            } message: {
                Text("Dein Beitrag wurde übermittelt und wird vor der Veröffentlichung geprüft.")
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await onSubmit(
                kind,
                cleanedTitle,
                cleanedDetail,
                notifyOnUpdates
            )
            showingSubmissionConfirmation = true
        } catch {
            errorMessage = "Der Beitrag konnte nicht gesendet werden. Bitte versuche es später erneut."
        }
    }
}

#Preview {
    NavigationStack {
        FeedbackView()
    }
}
