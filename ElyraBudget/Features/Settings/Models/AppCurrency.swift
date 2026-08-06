import Foundation

enum AppCurrency: String, CaseIterable, Identifiable {
    case eur = "EUR"
    case usd = "USD"
    case gbp = "GBP"
    case chf = "CHF"

    var id: Self { self }

    var title: String {
        switch self {
        case .eur: "Euro (€)"
        case .usd: "US-Dollar ($)"
        case .gbp: "Britisches Pfund (£)"
        case .chf: "Schweizer Franken (CHF)"
        }
    }
}
