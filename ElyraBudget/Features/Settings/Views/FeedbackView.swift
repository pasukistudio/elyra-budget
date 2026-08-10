import Foundation
import Combine
import SwiftUI

private enum FeedbackConfiguration {
    static let apiBaseURL = URL(string: "https://feedback.pasukistudio.de/api/v1")!
    static let supportEmail = "support@pasukistudio.de"
    static let installationIDKey = "feedback.installationID"
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

    init(fiderStatus: String?) {
        switch fiderStatus?.lowercased() {
        case "planned", "open": self = .planned
        case "started", "in_progress", "in-progress": self = .inProgress
        case "completed", "done": self = .completed
        case "under_review", "under-review": self = .underReview
        default: self = .underReview
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

private struct FeedbackListResponse: Codable {
    let items: [FeedbackPost]
}

private struct FiderPostsResponse: Decodable {
    let posts: [FiderPost]
}

private struct FiderPost: Decodable {
    let number: Int
    let title: String
    let description: String
    let status: String?
    let votesCount: Int
    let hasVoted: Bool?
    let createdAt: Date?

    private enum CodingKeys: String, CodingKey {
        case number
        case title
        case description
        case status
        case votesCount
        case hasVoted
        case createdAt
    }
}

private struct FiderPostRequest: Encodable {
    let title: String
    let description: String
}

private struct FeedbackSubmission: Codable {
    let kind: FeedbackKind
    let title: String
    let detail: String
    let installationID: String

    private enum CodingKeys: String, CodingKey {
        case kind = "type"
        case title
        case detail
        case installationID = "installationId"
    }
}

private struct FeedbackVoteRequest: Codable {
    let installationID: String

    private enum CodingKeys: String, CodingKey {
        case installationID = "installationId"
    }
}

private enum FeedbackServiceError: LocalizedError {
    case unauthorized
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Der Feedback-Server erlaubt diese Aktion aktuell nur für angemeldete Nutzer."
        case .unavailable:
            "Der Feedback-Server ist gerade nicht erreichbar. Bitte versuche es später erneut."
        }
    }
}

private extension FeedbackKind {
    var fiderTitlePrefix: String {
        switch self {
        case .feature: "[Feature]"
        case .bug: "[Bug]"
        }
    }

    static func fromFiderTitle(_ title: String) -> (kind: FeedbackKind, title: String) {
        if title.hasPrefix("[Bug] ") {
            return (.bug, String(title.dropFirst("[Bug] ".count)))
        }
        if title.hasPrefix("[Feature] ") {
            return (.feature, String(title.dropFirst("[Feature] ".count)))
        }
        return (.feature, title)
    }
}

private extension FeedbackPost {
    init(fiderPost: FiderPost) {
        let parsedTitle = FeedbackKind.fromFiderTitle(fiderPost.title)
        self.init(
            id: String(fiderPost.number),
            kind: parsedTitle.kind,
            title: parsedTitle.title,
            detail: fiderPost.description,
            state: FeedbackState(fiderStatus: fiderPost.status),
            voteCount: fiderPost.votesCount,
            hasVoted: fiderPost.hasVoted ?? false,
            createdAt: fiderPost.createdAt ?? .now
        )
    }
}

@MainActor
private final class FeedbackService: ObservableObject {
    @Published private(set) var posts: [FeedbackPost] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let session = URLSession.shared
    private let encoder = JSONEncoder()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    let installationID: String

    init() {
        if let storedID = UserDefaults.standard.string(forKey: FeedbackConfiguration.installationIDKey) {
            installationID = storedID
        } else {
            let newID = UUID().uuidString
            UserDefaults.standard.set(newID, forKey: FeedbackConfiguration.installationIDKey)
            installationID = newID
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let request = makeRequest(path: "posts", method: "GET")
            let (data, response) = try await session.data(for: request)
            try validate(response)

            let fiderPosts: [FiderPost]
            if let response = try? decoder.decode(FiderPostsResponse.self, from: data) {
                fiderPosts = response.posts
            } else {
                fiderPosts = try decoder.decode([FiderPost].self, from: data)
            }
            posts = fiderPosts.map(FeedbackPost.init(fiderPost:))
            errorMessage = nil
        } catch {
            errorMessage = "Feedback konnte gerade nicht geladen werden. Bitte versuche es später erneut."
        }
    }

    func submit(kind: FeedbackKind, title: String, detail: String) async throws {
        let payload = FiderPostRequest(
            title: "\(kind.fiderTitlePrefix) \(title)",
            description: detail
        )
        var request = makeRequest(path: "posts", method: "POST")
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await session.data(for: request)
        try validate(response)
        _ = data
        await load()
    }

    func toggleVote(for post: FeedbackPost) async throws {
        let request = makeRequest(path: "posts/\(post.id)/votes", method: "POST")
        let (data, response) = try await session.data(for: request)
        try validate(response)
        _ = data
        await load()
    }

    private func makeRequest(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: FeedbackConfiguration.apiBaseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedbackServiceError.unavailable
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw FeedbackServiceError.unauthorized
            }
            throw FeedbackServiceError.unavailable
        }
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
    @StateObject private var service = FeedbackService()
    @State private var filter: Filter = .roadmap
    @State private var composerKind: FeedbackKind = .feature
    @State private var showingComposer = false

    private var visiblePosts: [FeedbackPost] {
        switch filter {
        case .roadmap:
            service.posts
        case .features:
            service.posts.filter { $0.kind == .feature }
        case .bugs:
            service.posts.filter { $0.kind == .bug }
        }
    }

    var body: some View {
        List {
            Section {
                Label {
                    Text("Teile Ideen, melde Fehler und stimme direkt in der App ab – ganz ohne GitHub-Konto.")
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
                        Image(systemName: filter == .bugs ? "ladybug" : "lightbulb")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Noch keine Beiträge")
                            .font(.headline)
                        Text("Sei die erste Person mit einem Vorschlag.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
            } else {
                Section(filter == .roadmap ? "Aktuelle Beiträge" : filter.title) {
                    ForEach(visiblePosts) { post in
                        FeedbackPostRow(post: post) {
                            Task {
                                try? await service.toggleVote(for: post)
                            }
                        }
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
        .task { await service.load() }
        .sheet(isPresented: $showingComposer) {
            FeedbackComposerView(kind: composerKind) { kind, title, detail in
                try await service.submit(kind: kind, title: title, detail: detail)
            }
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
            .accessibilityLabel(post.hasVoted ? "Stimme entfernen" : "Für Beitrag abstimmen")
        }
        .padding(.vertical, 4)
    }
}

private struct FeedbackComposerView: View {
    let kind: FeedbackKind
    let onSubmit: (FeedbackKind, String, String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var detail = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(kind.title, systemImage: kind.icon)
                        .foregroundStyle(kind.tint)
                }

                Section("Dein Beitrag") {
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
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              isSubmitting)
                }
            }
            .overlay {
                if isSubmitting {
                    ProgressView()
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await onSubmit(
                kind,
                title.trimmingCharacters(in: .whitespacesAndNewlines),
                detail.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            dismiss()
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
