import SwiftData
import SwiftUI
import Charts

struct OverviewView: View {
    @Binding var selectedGroup: BudgetGroup?
    @Binding var selectedDate: Date

    @Environment(\.appCurrencyCode) private var currencyCode
    @Environment(ProAccessManager.self) private var proAccess
    @State private var dashboardPage = 0
    @State private var showingAnalytics = false
    @State private var showingProUpgrade = false
    @State private var showingSelectedGroupEditor = false

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

    @Query(
        filter: #Predicate<BudgetGroup> { !$0.isArchived },
        sort: [SortDescriptor<BudgetGroup>(\.sortOrder)]
    )
    private var budgetGroups: [BudgetGroup]

    @Query(
        filter: #Predicate<FixedCost> { !$0.isPaused },
        sort: [SortDescriptor<FixedCost>(\.createdAt)]
    )
    private var fixedCosts: [FixedCost]

    @Query(
        filter: #Predicate<SavingsGoal> { !$0.isArchived },
        sort: [SortDescriptor<SavingsGoal>(\.sortOrder)]
    )
    private var savingsGoals: [SavingsGoal]

    init(
        selectedGroup: Binding<BudgetGroup?> = .constant(nil),
        selectedDate: Binding<Date> = .constant(.now)
    ) {
        _selectedGroup = selectedGroup
        _selectedDate = selectedDate
    }

    private var visibleBudgets: [Budget] {
        budgets.filter { budget in
            selectedGroup == nil || budget.group === selectedGroup
        }
    }

    private var visibleTransactions: [Transaction] {
        transactions.filter { transaction in
            selectedGroup == nil || transaction.effectiveGroup === selectedGroup
        }
    }

    private var currentMonth: Date { selectedDate }

    private var monthlyLimit: Decimal {
        if let selectedGroup {
            return effectiveMonthlyBudget(for: selectedGroup)
        }

        var total = budgetGroups.reduce(into: Decimal.zero) { result, group in
            result += effectiveMonthlyBudget(for: group)
        }

        total += visibleBudgets
            .filter { $0.group == nil }
            .reduce(into: Decimal.zero) { $0 += $1.limit }
        return total
    }

    private func effectiveMonthlyBudget(for group: BudgetGroup) -> Decimal {
        let configured = group.monthlyBudget(for: currentMonth)
        guard configured <= 0 else { return configured }

        return budgets
            .filter { $0.group === group }
            .reduce(into: Decimal.zero) { $0 += $1.limit }
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

    private var statusColor: Color {
        switch monthlyProgress {
        case 0 ..< greenThreshold: return .green
        case greenThreshold ..< orangeThreshold: return .orange
        default: return .red
        }
    }

    private var statusTitle: LocalizedStringKey {
        switch monthlyProgress {
        case 0 ..< greenThreshold: return "Im grünen Bereich"
        case greenThreshold ..< orangeThreshold: return "Achte auf dein Budget"
        default: return "Budget überschritten"
        }
    }

    private var greenThreshold: Double {
        Double(selectedGroup?.greenBudgetThreshold ?? profiles.first?.greenBudgetThreshold ?? 70) / 100
    }

    private var orangeThreshold: Double {
        Double(selectedGroup?.orangeBudgetThreshold ?? profiles.first?.orangeBudgetThreshold ?? 100) / 100
    }

    private var monthlyExpenseTransactions: [Transaction] {
        visibleTransactions.filter {
            $0.date.isInSameMonth(as: currentMonth)
                && $0.type == .expense
        }
    }

    private var todayTransactions: [Transaction] {
        return visibleTransactions
            .filter {
                return $0.date.isInSameMonth(as: selectedDate)
            }
            .sorted { $0.date > $1.date }
    }

    private var budgetSpendings: [OverviewBudgetSpending] {
        visibleBudgets
            .map { budget in
                OverviewBudgetSpending(
                    name: budget.name,
                    amount: budgetUsage(for: budget),
                    color: Color(hexString: budget.iconColorHex)
                )
            }
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
    }

    private func budgetUsage(for budget: Budget) -> Decimal {
        visibleTransactions
            .filter {
                $0.budget === budget
                    && $0.date.isInSameMonth(as: currentMonth)
            }
            .reduce(.zero) { $0 + $1.budgetImpact }
    }

    private var monthInterval: DateInterval {
        Calendar.autoupdatingCurrent.dateInterval(of: .month, for: currentMonth)
            ?? DateInterval(start: currentMonth, duration: 0)
    }

    private var visibleFixedCosts: [FixedCostDueItem] {
        let bookedOccurrences = Set(
            transactions.compactMap { transaction -> String? in
                guard let fixedCostID = transaction.fixedCostID,
                      let occurrenceDate = transaction.fixedCostOccurrenceDate else {
                    return nil
                }
                return FixedCostScheduler.marker(for: fixedCostID, date: occurrenceDate)
            }
        )

        return fixedCosts
            .filter { cost in
                (selectedGroup == nil || cost.group === selectedGroup)
                    && cost.createdAt <= monthInterval.end
            }
            .flatMap { cost in
                cost.occurrenceDates(
                    from: monthInterval.start,
                    through: monthInterval.end
                )
                .filter { occurrenceDate in
                    let isBooked = bookedOccurrences.contains(
                        FixedCostScheduler.marker(for: cost.id, date: occurrenceDate)
                    )
                    return !isBooked
                }
                .map { FixedCostDueItem(fixedCost: cost, dueDate: $0) }
            }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var visibleSavingsGoals: [SavingsGoal] {
        savingsGoals.filter { goal in
            (selectedGroup == nil || goal.group === selectedGroup)
                && goal.createdAt <= monthInterval.end
        }
    }

    private var overviewBudgets: [Budget] {
        Array(visibleBudgets.sorted { lhs, rhs in
            let lhsUsage = budgetUsage(for: lhs)
            let rhsUsage = budgetUsage(for: rhs)
            let lhsIsOverLimit = lhs.limit > 0 && lhsUsage >= lhs.limit
            let rhsIsOverLimit = rhs.limit > 0 && rhsUsage >= rhs.limit
            let lhsProgress = lhs.limit > 0
                ? NSDecimalNumber(decimal: lhsUsage / lhs.limit).doubleValue
                : 0
            let rhsProgress = rhs.limit > 0
                ? NSDecimalNumber(decimal: rhsUsage / rhs.limit).doubleValue
                : 0

            if lhsIsOverLimit != rhsIsOverLimit {
                return lhsIsOverLimit
            }
            if lhsProgress != rhsProgress {
                return lhsProgress > rhsProgress
            }
            if lhsUsage != rhsUsage {
                return lhsUsage > rhsUsage
            }
            return lhs.sortOrder < rhs.sortOrder
        }.prefix(3))
    }

    private var overviewSavingsGoals: [SavingsGoal] {
        Array(visibleSavingsGoals.sorted { lhs, rhs in
            let lhsHasDate = lhs.targetDate != nil
            let rhsHasDate = rhs.targetDate != nil
            if lhsHasDate != rhsHasDate {
                return lhsHasDate
            }
            if let lhsDate = lhs.targetDate, let rhsDate = rhs.targetDate, lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            if lhs.visualProgress != rhs.visualProgress {
                return lhs.visualProgress < rhs.visualProgress
            }
            return lhs.sortOrder < rhs.sortOrder
        }.prefix(3))
    }

    private var totalSaved: Decimal {
        visibleSavingsGoals.reduce(.zero) { result, goal in
            result + goal.savedAmount(asOf: monthInterval.end.addingTimeInterval(-1))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                greetingSection
                dashboardCard
                periodOverviewCards
            }
            .padding()
        }
        #if os(macOS)
        .toolbar {
            ToolbarItem {
                Button {
                    if proAccess.hasPro {
                        showingAnalytics = true
                    } else {
                        showingProUpgrade = true
                    }
                } label: {
                    Label("Statistiken", systemImage: "chart.xyaxis.line")
                }
            }
        }
        #endif
        .sheet(isPresented: $showingAnalytics) {
            ProAnalyticsView(selectedDate: selectedDate, selectedGroup: selectedGroup)
        }
        .sheet(isPresented: $showingProUpgrade) {
            ProUpgradeView(feature: "Statistiken und Monatsberichte")
        }
        .sheet(isPresented: $showingSelectedGroupEditor) {
            if let selectedGroup {
                BudgetGroupEditorView(group: selectedGroup, selectedDate: selectedDate)
            }
        }
    }

    private var periodOverviewCards: some View {
        VStack(alignment: .leading, spacing: 24) {
            todayTransactionsCard
            budgetSnapshot
            fixedCostsSnapshot
            savingsSnapshot
        }
        #if os(iOS)
        .simultaneousGesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    handleMonthSwipe(value)
                }
        )
        #endif
    }

    #if os(iOS)
    private func handleMonthSwipe(_ value: DragGesture.Value) {
        let horizontalDistance = value.translation.width
        let verticalDistance = value.translation.height
        let minimumSwipeDistance: CGFloat = 60

        guard abs(horizontalDistance) >= minimumSwipeDistance,
              abs(horizontalDistance) > abs(verticalDistance) else {
            return
        }

        let periodOffset = horizontalDistance > 0 ? -1 : 1
        guard let newDate = Calendar.current.date(
            byAdding: .month,
            value: periodOffset,
            to: selectedDate
        ) else {
            return
        }

        withAnimation(.snappy) {
            selectedDate = newDate
        }
    }
    #endif

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

    // MARK: - Dashboard

    private var dashboardCard: some View {
        VStack(spacing: 8) {
            TabView(selection: $dashboardPage) {
                budgetSummaryPage
                    .tag(0)
                spendingDistributionPage
                    .tag(1)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #else
            .tabViewStyle(.automatic)
            #endif
            .frame(height: 260)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.primary.opacity(0.07), lineWidth: 1)
            }

            HStack(spacing: 6) {
                ForEach(0 ..< 2, id: \.self) { page in
                    Capsule(style: .continuous)
                        .fill(page == dashboardPage ? statusColor : Color.secondary.opacity(0.25))
                        .frame(width: page == dashboardPage ? 18 : 6, height: 6)
                        .animation(.easeInOut(duration: 0.2), value: dashboardPage)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Dashboard-Seite \(dashboardPage + 1) von 2")
        }
    }

    private var budgetSummaryPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Budgetstatus", systemImage: "chart.bar.fill")
                    .font(.headline)
                Spacer()
                Button {
                    showingSelectedGroupEditor = true
                } label: {
                    Label(
                        monthlyLimit > 0 ? "Anpassen" : "Festlegen",
                        systemImage: "pencil"
                    )
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(
                    monthlyLimit > 0
                        ? "Monatsbudget anpassen"
                        : "Monatsbudget festlegen"
                )
            }

            Text(selectedGroup?.name ?? "Bereich auswählen")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(statusTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(statusColor)
                    Text(monthlyAvailable, format: .currency(code: currencyCode))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                    Text("verfügbar in diesem Monat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Gauge(value: monthlyProgress, in: 0 ... 1) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(Int(monthlyProgress * 100)) %")
                        .font(.caption.weight(.bold))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(statusColor)
                .frame(width: 78, height: 78)
            }

            if monthlyLimit <= 0 {
                Text("Für diesen Bereich ist noch kein Monatsbudget festgelegt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(statusColor)
                .frame(height: 6)

            HStack(spacing: 0) {
                DashboardMetric(title: "Gesamt", value: monthlyLimit, currencyCode: currencyCode)
                Spacer()
                DashboardMetric(title: "Verwendet", value: monthlyUsed, currencyCode: currencyCode)
            }
        }
        .padding(20)
    }

    private var spendingDistributionPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ausgabenverteilung", systemImage: "chart.pie.fill")
                .font(.headline)

            if budgetSpendings.isEmpty {
                OverviewEmptyRow(text: "In diesem Monat gibt es noch keine Budgetausgaben.")
                    .frame(maxHeight: .infinity, alignment: .center)
            } else {
                HStack(spacing: 18) {
                    Chart(budgetSpendings) { spending in
                        SectorMark(
                            angle: .value("Ausgaben", NSDecimalNumber(decimal: spending.amount).doubleValue),
                            innerRadius: .ratio(0.58),
                            angularInset: 2
                        )
                        .foregroundStyle(spending.color)
                    }
                    .chartLegend(.hidden)
                    .frame(width: 128, height: 128)

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(budgetSpendings.prefix(4))) { spending in
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(spending.color)
                                    .frame(width: 8, height: 8)
                                Text(spending.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(spending.amount, format: .currency(code: currencyCode))
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(20)
    }

    private var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    private var todayTransactionsCard: some View {
        OverviewCard(title: "Buchungen", systemImage: "calendar") {
            if todayTransactions.isEmpty {
                OverviewEmptyRow(text: "In diesem Monat gibt es keine Buchungen.")
            } else {
                ForEach(Array(todayTransactions.prefix(4)), id: \.persistentModelID) { transaction in
                    HStack(spacing: 10) {
                        Image(systemName: transaction.type.systemImage)
                            .foregroundStyle(transaction.type == .expense ? Color.red : Color.green)
                            .frame(width: 24)
                        Text(transaction.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text(transaction.signedAmount, format: .currency(code: currencyCode))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(transaction.type == .expense ? Color.red : Color.green)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var budgetSnapshot: some View {
        OverviewCard(title: "Budgets", systemImage: "chart.bar.fill") {
            if visibleBudgets.isEmpty {
                OverviewEmptyRow(text: "Noch keine Budgets angelegt.")
            } else {
                ForEach(overviewBudgets, id: \.persistentModelID) { budget in
                    OverviewBudgetRow(
                        budget: budget,
                        transactions: visibleTransactions,
                        month: currentMonth,
                        currencyCode: currencyCode
                    )
                }
            }
        }
    }

    private var fixedCostsSnapshot: some View {
        OverviewCard(title: "Nächste Fixkosten", systemImage: "calendar.badge.clock") {
            if visibleFixedCosts.isEmpty {
                OverviewEmptyRow(text: "In diesem Monat sind keine Fixkosten geplant.")
            } else {
                ForEach(Array(visibleFixedCosts.prefix(3))) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.fixedCost.title).font(.subheadline.weight(.semibold))
                            Text(item.dueDate, format: .dateTime.day().month(.abbreviated))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.fixedCost.amount, format: .currency(code: currencyCode))
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }

    private var savingsSnapshot: some View {
        OverviewCard(title: "Sparen", systemImage: "banknote.fill") {
            if visibleSavingsGoals.isEmpty {
                OverviewEmptyRow(text: "Noch keine Sparziele oder Rücklagen angelegt.")
            } else {
                HStack {
                    Text("Gespart")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(totalSaved, format: .currency(code: currencyCode))
                        .font(.subheadline.weight(.semibold))
                }

                ForEach(overviewSavingsGoals, id: \.persistentModelID) { goal in
                    HStack(spacing: 12) {
                        IconBadgeView(
                            iconName: goal.iconName,
                            color: Color(hexString: goal.iconColorHex),
                            size: 32
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.name).font(.subheadline.weight(.semibold))
                            if let target = goal.targetAmount, target > 0 {
                                Text("von \(target, format: .currency(code: currencyCode))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Freie Rücklage")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if goal.targetAmount != nil {
                            ProgressRingView(
                                progress: goal.visualProgress,
                                color: Color(hexString: goal.iconColorHex)
                            )
                        } else {
                            Text(goal.savedAmount(asOf: monthInterval.end.addingTimeInterval(-1)), format: .currency(code: currencyCode))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
        }
    }

}

private struct OverviewCard<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder let content: () -> Content

    init(
        title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.primary.opacity(0.07), lineWidth: 1)
        }
    }

    private var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

private struct ProgressRingView: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.16), lineWidth: 4)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))%")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(width: 42, height: 42)
        .accessibilityLabel("Fortschritt")
        .accessibilityValue("\(Int(progress * 100)) Prozent")
    }
}

private struct DashboardMetric: View {
    let title: LocalizedStringKey
    let value: Decimal
    let currencyCode: String?
    let suffix: String?

    init(
        title: LocalizedStringKey,
        value: Decimal,
        currencyCode: String? = nil,
        suffix: String? = nil
    ) {
        self.title = title
        self.value = value
        self.currencyCode = currencyCode
        self.suffix = suffix
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let currencyCode {
                Text(value, format: .currency(code: currencyCode))
                    .font(.caption.weight(.semibold))
            } else {
                Text("\(NSDecimalNumber(decimal: value).doubleValue, specifier: "%.0f")\(suffix ?? "")")
                    .font(.caption.weight(.semibold))
            }
        }
    }
}

private struct OverviewBudgetSpending: Identifiable {
    let id = UUID()
    let name: String
    let amount: Decimal
    let color: Color
}

private struct OverviewEmptyRow: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

private struct OverviewBudgetRow: View {
    let budget: Budget
    let transactions: [Transaction]
    let month: Date
    let currencyCode: String

    private var spent: Decimal {
        transactions
            .filter { $0.budget === budget && $0.date.isInSameMonth(as: month) }
            .reduce(.zero) { $0 + $1.budgetImpact }
    }
    private var remaining: Decimal? { budget.limit > 0 ? budget.limit - spent : nil }
    private var progress: Double {
        guard budget.limit > 0 else { return 0 }
        return min(max(NSDecimalNumber(decimal: spent / budget.limit).doubleValue, 0), 1)
    }

    var body: some View {
        let remainingAmount = remaining ?? 0
        let isWithinLimit = remainingAmount >= 0
        let accentColor = Color(hexString: budget.iconColorHex)

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                BudgetIconView(budget: budget)
                Text(budget.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(spent, format: .currency(code: currencyCode))
                    .font(.subheadline.weight(.semibold))
            }

            if budget.limit > 0 {
                ProgressView(value: progress)
                    .tint(isWithinLimit ? accentColor : .red)
                Text(isWithinLimit
                     ? "Verfügbar \(remainingAmount, format: .currency(code: currencyCode))"
                     : "Über Limit \(abs(remainingAmount), format: .currency(code: currencyCode))")
                    .font(.caption)
                    .foregroundStyle(isWithinLimit ? Color.secondary : Color.red)
            } else {
                Text("Kein Limit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    OverviewView()
}
