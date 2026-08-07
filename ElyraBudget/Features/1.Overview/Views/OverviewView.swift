import SwiftData
import SwiftUI

struct OverviewView: View {
    @Binding var selectedGroup: BudgetGroup?

    @Environment(\.appCurrencyCode) private var currencyCode

    @Query(
        filter: #Predicate<Budget> { !$0.isArchived },
        sort: [
            SortDescriptor<Budget>(\.sortOrder),
            SortDescriptor<Budget>(\.createdAt)
        ]
    )
    private var budgets: [Budget]

    @Query(sort: [SortDescriptor<Transaction>(\.date)])
    private var transactions: [Transaction]

    init(selectedGroup: Binding<BudgetGroup?> = .constant(nil)) {
        _selectedGroup = selectedGroup
    }

    private var visibleBudgets: [Budget] {
        budgets.filter { budget in
            selectedGroup == nil || budget.group === selectedGroup
        }
    }

    private var visibleTransactions: [Transaction] {
        transactions.filter { transaction in
            selectedGroup == nil
                || transaction.group === selectedGroup
                || transaction.budget?.group === selectedGroup
        }
    }

    private var currentMonth: Date { .now }

    private var monthlyLimit: Decimal {
        visibleBudgets.reduce(into: Decimal.zero) { result, budget in
            result += budget.limit
        }
    }

    private var monthlyUsed: Decimal {
        visibleTransactions
            .filter { $0.date.isInSameMonth(as: currentMonth) }
            .reduce(into: Decimal.zero) { result, transaction in
                result += transaction.budgetImpact
            }
    }

    private var monthlyAvailable: Decimal {
        monthlyLimit - monthlyUsed
    }

    private var monthlyProgress: Double {
        guard monthlyLimit > 0 else { return 0 }
        return min(
            max(
                NSDecimalNumber(decimal: monthlyUsed).doubleValue
                    / NSDecimalNumber(decimal: monthlyLimit).doubleValue,
                0
            ),
            1
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                greetingSection
                #if os(iOS)
                    availableBudgetCard
                #endif
            }
            .padding()
        }
    }

    // MARK: - Begrüßung

    @Query(
        sort: \UserSettings.updatedAt,
        order: .reverse
    )
    private var profiles: [UserSettings]

    private var greetingSection: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greetingText)
                    .font(
                        displayName.isEmpty
                            ? .title2.bold()
                            : .subheadline
                    )
                    .foregroundStyle(
                        displayName.isEmpty
                            ? .primary
                            : .secondary
                    )

                if !displayName.isEmpty {
                    Text(displayName)
                        .font(.title2.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(
                    Date.now,
                    format: .dateTime
                        .weekday(.wide)
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Text(
                    Date.now,
                    format: .dateTime
                        .day(.twoDigits)
                        .month(.wide)
                )
                .font(.headline)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var cleanedFullName: String {
        profiles.first?.name
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? ""
    }

    private var displayName: String {
        guard !cleanedFullName.isEmpty else {
            return ""
        }

        return cleanedFullName
            .split(separator: " ")
            .first
            .map(String.init)
            ?? cleanedFullName
    }

    private var greetingText: LocalizedStringResource {
        displayName.isEmpty
            ? currentDayPeriod.greetingWithoutComma
            : currentDayPeriod.greeting
    }

    private var currentDayPeriod: DayPeriod {
        let hour = Calendar.current.component(
            .hour,
            from: Date()
        )

        switch hour {
        case 5 ..< 11:
            return .morning

        case 11 ..< 14:
            return .noon

        case 14 ..< 18:
            return .afternoon

        case 18 ..< 23:
            return .evening

        default:
            return .night
        }
    }

    private enum DayPeriod {
        case morning
        case noon
        case afternoon
        case evening
        case night

        var greeting: LocalizedStringResource {
            switch self {
            case .morning:
                return "Guten Morgen,"

            case .noon:
                return "Guten Mittag,"

            case .afternoon:
                return "Guten Nachmittag,"

            case .evening:
                return "Guten Abend,"

            case .night:
                return "Gute Nacht,"
            }
        }

        var greetingWithoutComma: LocalizedStringResource {
            switch self {
            case .morning:
                return "Guten Morgen"

            case .noon:
                return "Guten Mittag"

            case .afternoon:
                return "Guten Nachmittag"

            case .evening:
                return "Guten Abend"

            case .night:
                return "Gute Nacht"
            }
        }
    }

    // MARK: - Verfügbares Budget

    private var availableBudgetCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Verfügbar in diesem Monat")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(monthlyAvailable, format: .currency(code: currencyCode))
                .font(.system(size: 42, weight: .bold))

            if monthlyLimit > 0 {
                ProgressView(value: monthlyProgress)
                    .tint(.primary)
            }

            HStack {
                Label {
                    HStack(spacing: 4) {
                        Text(monthlyUsed, format: .currency(code: currencyCode))
                        Text("verwendet")
                    }
                } icon: {
                    Image(systemName: "arrow.up.right")
                }

                Spacer()

                if monthlyLimit > 0 {
                    Text("Limit \(monthlyLimit.formatted(.currency(code: currencyCode)))")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .orange.gradient,
            in: RoundedRectangle(cornerRadius: 24)
        )
        .foregroundStyle(.white)
    }
}

#Preview {
    OverviewView()
}
