//
//  MonthPickerSheet.swift
//  ElyraBudget
//
//  Created by Pascal Smigielski on 04.08.26.
//

import SwiftUI

struct MonthPickerSheet: View {
    // MARK: - Bindings & Environment

    @Binding var selectedDate: Date

    @Environment(\.dismiss) private var dismiss

    // MARK: - Hilfswerte

    private let calendar = Calendar.current

    init(
        selectedDate: Binding<Date>
    ) {
        _selectedDate = selectedDate
    }

    // MARK: - Auswahlbindungen

    private var selectedMonth: Binding<Int> {
        Binding(
            get: {
                calendar.component(
                    .month,
                    from: selectedDate
                )
            },
            set: { newMonth in
                updateDate(month: newMonth)
            }
        )
    }

    private var selectedYear: Binding<Int> {
        Binding(
            get: {
                calendar.component(
                    .year,
                    from: selectedDate
                )
            },
            set: { newYear in
                updateDate(year: newYear)
            }
        )
    }

    // MARK: - Verfügbare Jahre

    private var availableYears: [Int] {
        let currentYear = calendar.component(
            .year,
            from: Date()
        )

        return Array(
            (currentYear - 10) ... (currentYear + 10)
        )
    }

    // MARK: - Ansicht

    var body: some View {
        NavigationStack {
            Form {
                monthPicker
                yearPicker
            }
            .navigationTitle("Monat auswählen")
            .toolbar {
                confirmationToolbar
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Monatsauswahl

    private var monthPicker: some View {
        Picker(
            "Monat",
            selection: selectedMonth
        ) {
            ForEach(1 ... 12, id: \.self) { month in
                Text(monthName(for: month))
                    .tag(month)
            }
        }
    }

    // MARK: - Jahresauswahl

    private var yearPicker: some View {
        Picker(
            "Jahr",
            selection: selectedYear
        ) {
            ForEach(
                availableYears,
                id: \.self
            ) { year in
                Text(String(year))
                    .tag(year)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var confirmationToolbar: some ToolbarContent {
        ToolbarItem(
            placement: .confirmationAction
        ) {
            Button("Fertig") {
                dismiss()
            }
        }
    }

    // MARK: - Monatsname

    private func monthName(
        for month: Int
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current

        return formatter
            .monthSymbols[month - 1]
            .capitalized
    }

    // MARK: - Datum aktualisieren

    private func updateDate(
        month: Int? = nil,
        year: Int? = nil
    ) {
        var components = calendar.dateComponents(
            [.year, .month],
            from: selectedDate
        )

        if let month {
            components.month = month
        }

        if let year {
            components.year = year
        }

        components.day = 1

        guard let newDate = calendar.date(
            from: components
        ) else {
            return
        }

        selectedDate = newDate
    }
}
