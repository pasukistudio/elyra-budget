import SwiftUI

struct MonthNavigationControl: View {

    // MARK: - Anzeige

    let title: String

    // MARK: - Aktionen

    let onPrevious: () -> Void
    let onSelectDate: () -> Void
    let onNext: () -> Void

    // MARK: - Ansicht

    var body: some View {
        HStack(spacing: 10) {
            previousButton
            monthButton
            nextButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(
            .regular,
            in: Capsule()
        )
    }

    // MARK: - Vorheriger Monat

    private var previousButton: some View {
        Button(
            action: onPrevious
        ) {
            Image(systemName: "chevron.left")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Vorheriger Monat")
    }

    // MARK: - Monatsauswahl

    private var monthButton: some View {
        Button(
            action: onSelectDate
        ) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 100)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Monat auswählen")
    }

    // MARK: - Nächster Monat

    private var nextButton: some View {
        Button(
            action: onNext
        ) {
            Image(systemName: "chevron.right")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Nächster Monat")
    }
}
