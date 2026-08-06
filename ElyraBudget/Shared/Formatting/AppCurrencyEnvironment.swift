import SwiftUI

private struct AppCurrencyCodeKey: EnvironmentKey {
    static let defaultValue = AppCurrency.eur.rawValue
}

extension EnvironmentValues {
    var appCurrencyCode: String {
        get { self[AppCurrencyCodeKey.self] }
        set { self[AppCurrencyCodeKey.self] = newValue }
    }
}
