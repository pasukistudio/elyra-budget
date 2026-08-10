import SwiftData
import SwiftUI

struct RecurringTransactionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCurrencyCode) private var currencyCode
    @Environment(ProAccessManager.self) private var proAccess

    @Query(sort: [SortDescriptor<Transaction>(\.date, order: .reverse)])
    private var transactions: [Transaction]
    @Query private var fixedCosts: [FixedCost]

    let selectedGroup: BudgetGroup?
    @State private var showingUpgrade = false
    @State private var addedTitles: Set<String> = []

    private var candidates: [RecurringTransactionCandidate] {
        RecurringTransactionDetector.detect(in: transactions.filter {
            selectedGroup == nil || $0.effectiveGroup === selectedGroup
        })
    }

    var body: some View {
        NavigationStack {
            Group {
                if !proAccess.hasPro {
                    ProUpgradeView(feature: "Wiederkehrende Buchungen")
                } else if candidates.isEmpty {
                    ContentUnavailableView(
                        "Keine Muster gefunden",
                        systemImage: "arrow.triangle.2.circlepath",
                        description: Text("Sobald eine Ausgabe regelmäßig wiederkehrt, wird sie hier vorgeschlagen.")
                    )
                } else {
                    List(candidates) { candidate in
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.title).font(.headline)
                                Text("\(candidate.occurrenceCount) Buchungen · ungefähr monatlich")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                Text(candidate.amount, format: .currency(code: currencyCode))
                                    .font(.headline)
                                Button(addedTitles.contains(candidate.title) ? "Hinzugefügt" : "Als Fixkosten übernehmen") {
                                    addFixedCost(candidate)
                                }
                                .font(.caption)
                                .disabled(addedTitles.contains(candidate.title))
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle("Wiederkehrende Buchungen")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .sheet(isPresented: $showingUpgrade) {
                ProUpgradeView(feature: "Wiederkehrende Buchungen")
            }
        }
    }

    private func addFixedCost(_ candidate: RecurringTransactionCandidate) {
        guard proAccess.hasPro else { showingUpgrade = true; return }
        let fixedCost = FixedCost(
            title: candidate.title,
            amount: candidate.amount,
            frequency: .monthly,
            anchorDate: candidate.lastDate,
            budget: candidate.budget,
            group: candidate.group
        )
        modelContext.insert(fixedCost)
        do {
            try modelContext.save()
            addedTitles.insert(candidate.title)
        } catch {
            // The editor's regular save-error presentation remains the source of truth.
        }
    }
}
