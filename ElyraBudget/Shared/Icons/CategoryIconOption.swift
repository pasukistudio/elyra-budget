import Foundation

struct CategoryIconOption: Identifiable, Hashable {

    // MARK: - Eigenschaften

    let systemName: String
    let keywords: [String: [String]]

    // MARK: - Identifiable

    var id: String {
        systemName
    }

    // MARK: - Suche

    func matches(
        _ searchText: String,
        locale: Locale
    ) -> Bool {
        let normalizedSearchText =
            searchText.normalizedForSearch

        guard !normalizedSearchText.isEmpty else {
            return true
        }

        let languageCode =
            locale.language.languageCode?.identifier
            ?? "en"

        let localizedKeywords =
            keywords[languageCode]
            ?? keywords["en"]
            ?? []

        let searchableTerms =
            [systemName] + localizedKeywords

        return searchableTerms.contains { term in
            term.normalizedForSearch
                .contains(normalizedSearchText)
        }
    }
}

// MARK: - Suchnormalisierung

private extension String {

    var normalizedForSearch: String {
        trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        .folding(
            options: [
                .caseInsensitive,
                .diacriticInsensitive
            ],
            locale: .current
        )
    }
}
