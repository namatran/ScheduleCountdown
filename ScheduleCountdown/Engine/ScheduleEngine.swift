import Foundation

/// Where you are in the school day at a given moment.
struct DayStatus: Equatable {
    /// Today's schedule, or nil on weekends and no-school days.
    var schedule: Schedule?
    /// Today's blocks for your lunch group, in time order.
    var blocks: [Block] = []
    var currentBlock: Block?
    /// The next block that hasn't started yet.
    var nextBlock: Block?
    /// Between the first and last bell of the day.
    var inSession = false
    /// The next bell today, if there is one left.
    var nextBell: Date?

    /// "4th", "Passing", or nil outside school hours.
    var label: String? {
        if let currentBlock { return currentBlock.name }
        return inSession ? "Passing" : nil
    }
}

/// Pure schedule logic: no clocks, timers or I/O, so it's easy to test.
struct ScheduleEngine {
    var master: MasterFile
    var calendar: Calendar = .current

    /// The schedule for a day. Calendar entries win over everything (the shortest
    /// matching range wins, so one day inside a break can still be a school day);
    /// otherwise weekends are off and weekdays use the default schedule.
    func schedule(on date: Date) -> Schedule? {
        let day = DayDate(date, calendar: calendar)
        let matches = master.calendar.filter { $0.contains(day) }
        if let entry = matches.min(by: { span($0) < span($1) }) {
            guard let id = entry.scheduleID else { return nil }
            return master.schedule(id: id) ?? master.schedule(id: master.defaultScheduleID)
        }
        if calendar.isDateInWeekend(date) { return nil }
        return master.schedule(id: master.defaultScheduleID)
    }

    /// Every bell you hear today, in order: one-off bells, block starts, and block ends
    /// (or the dismiss bell when a block lets out early).
    func bells(for schedule: Schedule, lunch: LunchGroup, on date: Date) -> [Date] {
        let times = schedule.bells.map(\.time)
            + schedule.blocks(for: lunch).flatMap { [$0.start, $0.effectiveEnd] }
        return Set(times).sorted().map { $0.date(on: date, calendar: calendar) }
    }

    func status(at now: Date, lunch: LunchGroup) -> DayStatus {
        guard let schedule = schedule(on: now) else { return DayStatus() }

        let blocks = schedule.blocks(for: lunch)
        let bells = bells(for: schedule, lunch: lunch, on: now)
        func date(_ time: ClockTime) -> Date { time.date(on: now, calendar: calendar) }

        var status = DayStatus(schedule: schedule, blocks: blocks)
        status.currentBlock = blocks.first { date($0.start) <= now && now < date($0.effectiveEnd) }
        status.nextBlock = blocks.first { date($0.start) > now }
        if let first = bells.first, let last = bells.last {
            status.inSession = first <= now && now < last
        }
        status.nextBell = bells.first { $0 > now }
        return status
    }

    /// The next bell from now, looking ahead across days (for the "outside school hours" countdown).
    func nextBell(after now: Date, lunch: LunchGroup, lookAheadDays: Int = 30) -> Date? {
        if let today = status(at: now, lunch: lunch).nextBell { return today }
        let startOfToday = calendar.startOfDay(for: now)
        for offset in 1...lookAheadDays {
            let day = calendar.date(byAdding: .day, value: offset, to: startOfToday)!
            if let schedule = schedule(on: day),
               let first = bells(for: schedule, lunch: lunch, on: day).first {
                return first
            }
        }
        return nil
    }

    private func span(_ entry: CalendarEntry) -> Int {
        calendar.dateComponents([.day], from: entry.start.date(calendar: calendar),
                                to: entry.end.date(calendar: calendar)).day ?? 0
    }
}

enum Countdown {
    /// "4:59", "12:03", "1:02:03", or "2d 3h" for very long waits.
    static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
