import SwiftUI
import SwiftData

struct OverviewView: View {
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
        case 5..<11:
            return .morning

        case 11..<14:
            return .noon

        case 14..<18:
            return .afternoon

        case 18..<23:
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

            Text(407.57, format: .currency(code: "EUR"))
                .font(.system(size: 42, weight: .bold))

            ProgressView(value: 2_228.25, total: 2_635.82)
                .tint(.primary)

            HStack {
                Label(
                    "2.228,25 € verwendet",
                    systemImage: "arrow.up.right"
                )

                Spacer()

                Text("Limit 2.635,82 €")
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
