import Foundation

struct RecurringTransactionCandidate: Identifiable {
    let id = UUID()
    let title: String
    let amount: Decimal
    let lastDate: Date
    let budget: Budget?
    let group: BudgetGroup?
    let occurrenceCount: Int
}

enum RecurringTransactionDetector {
    static func detect(in transactions: [Transaction]) -> [RecurringTransactionCandidate] {
        let expenseTransactions = transactions.filter { $0.type == .expense }
        let grouped = Dictionary(grouping: expenseTransactions) { normalize($0.title) }

        return grouped.compactMap { _, rows in
            let sorted = rows.sorted { $0.date < $1.date }
            guard sorted.count >= 2 else { return nil }
            let gaps = zip(sorted, sorted.dropFirst()).map { $1.date.timeIntervalSince($0.date) / 86_400 }
            let monthlyGaps = gaps.filter { 20...40 ~= $0 }
            guard monthlyGaps.count >= 1 else { return nil }
            let average = sorted.reduce(Decimal.zero) { $0 + abs($1.amount) } / Decimal(sorted.count)
            let stable = sorted.allSatisfy { amountDifference(abs($0.amount), average) <= 0.1 }
            guard stable else { return nil }
            guard let latest = sorted.last else { return nil }
            return RecurringTransactionCandidate(
                title: latest.title,
                amount: average,
                lastDate: latest.date,
                budget: latest.budget,
                group: latest.effectiveGroup,
                occurrenceCount: sorted.count
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func amountDifference(_ lhs: Decimal, _ rhs: Decimal) -> Decimal {
        guard rhs > 0 else { return 1 }
        return abs(lhs - rhs) / rhs
    }
}
