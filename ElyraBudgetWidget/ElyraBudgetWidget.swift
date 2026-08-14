import Foundation
import SwiftUI
import WidgetKit

private let widgetAppGroup = "group.de.pasukistudio.elyrabudget"
private let widgetSnapshotKey = "elyraBudget.widget.snapshot"

private struct WidgetSnapshot: Codable {
    let groupName: String
    let spent: Decimal
    let budget: Decimal
    let savingsProgress: Double
    let currencyCode: String
    let updatedAt: Date
}

private struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, snapshot: WidgetSnapshot(
            groupName: "Mein Bereich",
            spent: 420,
            budget: 1000,
            savingsProgress: 0.45,
            currencyCode: "EUR",
            updatedAt: .now
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Entry(date: .now, snapshot: loadSnapshot())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(900))))
    }

    private func loadSnapshot() -> WidgetSnapshot? {
        guard FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: widgetAppGroup
        ) != nil,
        let data = UserDefaults(suiteName: widgetAppGroup)?.data(forKey: widgetSnapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

private struct ElyraBudgetWidgetView: View {
    let entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let snapshot = entry.snapshot {
                Text(snapshot.groupName)
                    .font(.headline)
                    .lineLimit(1)
                Text(snapshot.spent, format: .currency(code: snapshot.currencyCode))
                    .font(.title2.bold())
                if snapshot.budget > 0 {
                    ProgressView(value: NSDecimalNumber(decimal: snapshot.spent / snapshot.budget).doubleValue)
                        .tint(snapshot.spent <= snapshot.budget ? .green : .red)
                    Text("von \(snapshot.budget, format: .currency(code: snapshot.currencyCode))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Ausgaben in diesem Monat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Label("Sparen \(Int(snapshot.savingsProgress * 100)) %", systemImage: "target")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "chart.pie.fill")
                    .font(.title)
                Text("Elyra Budget öffnen")
                    .font(.headline)
                Text("Füge einen Budgetbereich hinzu, um das Widget zu verwenden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct ElyraBudgetWidget: Widget {
    let kind = "ElyraBudgetWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ElyraBudgetWidgetView(entry: entry)
        }
        .configurationDisplayName("Elyra Budget")
        .description("Zeigt Ausgaben, Budget und Sparfortschritt.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct ElyraBudgetWidgetBundle: WidgetBundle {
    var body: some Widget {
        ElyraBudgetWidget()
    }
}
