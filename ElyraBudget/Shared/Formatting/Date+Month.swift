import Foundation

extension Date {
    func isInSameMonth(
        as otherDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        let components: Set<Calendar.Component> = [.year, .month]
        return calendar.dateComponents(components, from: self)
            == calendar.dateComponents(components, from: otherDate)
    }
}
