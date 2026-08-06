import SwiftUI

struct TransactionDaySectionHeader: View {
    let date: Date

    var body: some View {
        Text(title)
    }

    private var title: String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Heute"
        }

        if calendar.isDateInYesterday(date) {
            return "Gestern"
        }

        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
