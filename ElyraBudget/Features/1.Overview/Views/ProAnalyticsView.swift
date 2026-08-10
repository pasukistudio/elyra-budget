import Charts
import SwiftData
import SwiftUI

struct ProAnalyticsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProAccessManager.self) private var proAccess
    @Environment(\.appCurrencyCode) private var currencyCode

    @Query(sort: [SortDescriptor<Transaction>(\.date)])
    private var transactions: [Transaction]

    @Query(sort: [SortDescriptor<BudgetGroup>(\.sortOrder)])
    private var groups: [BudgetGroup]

    let selectedDate: Date
    let selectedGroup: BudgetGroup?
    @State private var exportURL: URL?
    @State private var showingUpgrade = false
    @State private var errorMessage: String?

    private var visibleTransactions: [Transaction] {
        transactions.filter {
            $0.date.isInSameMonth(as: selectedDate)
                && (selectedGroup == nil || $0.effectiveGroup === selectedGroup)
        }
    }

    private var expenses: Decimal {
        visibleTransactions.filter { $0.type == .expense }
            .reduce(.zero) { $0 + abs($1.amount) }
    }

    private var income: Decimal {
        visibleTransactions.filter { $0.type == .income }
            .reduce(.zero) { $0 + abs($1.amount) }
    }

    private var refunds: Decimal {
        visibleTransactions.filter { $0.type == .refund }
            .reduce(.zero) { $0 + abs($1.amount) }
    }

    private var categorySpending: [AnalyticsCategory] {
        Dictionary(grouping: visibleTransactions.filter { $0.type == .expense }) {
            $0.budget?.name ?? "Ohne Budget"
        }
        .map { name, rows in
            AnalyticsCategory(name: name, amount: rows.reduce(.zero) { $0 + abs($1.amount) })
        }
        .sorted { $0.amount > $1.amount }
    }

    var body: some View {
        NavigationStack {
            Group {
                if proAccess.hasPro {
                    analyticsContent
                } else {
                    ProUpgradeView(feature: "Statistiken und Monatsberichte")
                }
            }
            .navigationTitle("Statistiken")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .sheet(item: Binding(
                get: { exportURL.map(AnalyticsExportFile.init) },
                set: { exportURL = $0?.url }
            )) { file in
                ShareLink(item: file.url) {
                    Label("Bericht teilen", systemImage: "square.and.arrow.up")
                        .padding()
                }
                .presentationDetents([.height(140)])
            }
            .alert("Bericht nicht möglich", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Der Bericht konnte nicht erstellt werden.")
            }
        }
    }

    private var analyticsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(selectedDate, format: .dateTime.month(.wide).year())
                    .font(.title3.bold())

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    AnalyticsMetric(title: "Ausgaben", value: expenses, color: .red, currencyCode: currencyCode)
                    AnalyticsMetric(title: "Einnahmen", value: income, color: .green, currencyCode: currencyCode)
                    AnalyticsMetric(title: "Rückerstattungen", value: refunds, color: .teal, currencyCode: currencyCode)
                    AnalyticsMetric(title: "Buchungen", value: Decimal(visibleTransactions.count), color: .orange, currencyCode: nil)
                }

                if !categorySpending.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ausgaben nach Budget").font(.headline)
                        Chart(categorySpending) { category in
                            BarMark(x: .value("Betrag", NSDecimalNumber(decimal: category.amount).doubleValue), y: .value("Budget", category.name))
                                .foregroundStyle(.tint)
                        }
                        .frame(height: max(160, CGFloat(categorySpending.count * 42)))
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }

                Button(action: exportReport) {
                    Label("Monatsbericht als PDF teilen", systemImage: "doc.richtext")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private func exportReport() {
        do {
            exportURL = try TransactionExportService.write(
                transactions: visibleTransactions,
                month: selectedDate,
                currencyCode: currencyCode,
                format: .pdf
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AnalyticsCategory: Identifiable {
    let id = UUID()
    let name: String
    let amount: Decimal
}

private struct AnalyticsMetric: View {
    let title: String
    let value: Decimal
    let color: Color
    let currencyCode: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if let currencyCode {
                Text(value, format: .currency(code: currencyCode)).font(.headline)
            } else {
                Text(NSDecimalNumber(decimal: value).intValue, format: .number)
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AnalyticsExportFile: Identifiable {
    let url: URL
    var id: URL { url }
}
