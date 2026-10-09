import Foundation
import Testing
@testable import ScheduleCountdown

// Week of Oct 5, 2026: Mon 5 ... Fri 9, Sat 10, Sun 11.
private let calendar = Calendar.current

private func at(_ day: Int, _ hour: Int, _ minute: Int, month: Int = 10) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

private func engine(calendar entries: [CalendarEntry] = []) -> ScheduleEngine {
    var master = MasterFile.bundled()
    master.calendar = entries
    return ScheduleEngine(master: master, calendar: calendar)
}

private func assign(_ scheduleID: String?, _ start: String, through end: String? = nil) -> CalendarEntry {
    CalendarEntry(start: DayDate(start)!, end: DayDate(end ?? start)!, scheduleID: scheduleID)
}

struct ScheduleEngineTests {
    // MARK: Picking the day's schedule

    @Test func weekdaysUseTheDefaultSchedule() {
        #expect(engine().schedule(on: at(8, 9, 0))?.id == "normal")
    }

    @Test func weekendsHaveNoSchool() {
        #expect(engine().schedule(on: at(10, 9, 0)) == nil)
        #expect(engine().status(at: at(10, 9, 0), lunch: .a) == DayStatus())
    }

    @Test func calendarAssignsAlternateSchedules() {
        let e = engine(calendar: [assign("jamboree", "2026-10-09")])
        #expect(e.schedule(on: at(9, 9, 0))?.id == "jamboree")
        #expect(e.schedule(on: at(8, 9, 0))?.id == "normal")
    }

    @Test func noSchoolRangesCoverEveryDay() {
        let e = engine(calendar: [assign(nil, "2026-11-23", through: "2026-11-27")])
        for day in 23...27 { #expect(e.schedule(on: at(day, 9, 0, month: 11)) == nil) }
        #expect(e.schedule(on: at(30, 9, 0, month: 11))?.id == "normal")
    }

    @Test func singleDayBeatsSurroundingRange() {
        let e = engine(calendar: [assign(nil, "2026-12-14", through: "2026-12-18"), assign("pep-rally", "2026-12-16")])
        #expect(e.schedule(on: at(16, 9, 0, month: 12))?.id == "pep-rally")
        #expect(e.schedule(on: at(15, 9, 0, month: 12)) == nil)
    }

    @Test func unknownScheduleFallsBackToDefault() {
        let e = engine(calendar: [assign("deleted-schedule", "2026-10-09")])
        #expect(e.schedule(on: at(9, 9, 0))?.id == "normal")
    }

    // MARK: Normal schedule

    @Test func beforeReleaseIsOutsideSchoolHours() {
        let s = engine().status(at: at(8, 7, 0), lunch: .a)
        #expect(!s.inSession)
        #expect(s.label == nil)
        #expect(s.nextBell == at(8, 7, 9))
    }

    @Test func releaseBellStartsPassing() {
        let s = engine().status(at: at(8, 7, 10), lunch: .b)
        #expect(s.label == "Passing")
        #expect(s.nextBell == at(8, 7, 15))
        #expect(s.nextBlock?.name == "1st")
    }

    @Test func inClassCountsToTheEnd() {
        let s = engine().status(at: at(8, 10, 0), lunch: .c)
        #expect(s.label == "4th")
        #expect(s.nextBell == at(8, 10, 45))
        #expect(s.nextBlock?.name == "Advisory")
    }

    @Test func aLunchCountsToTheDismissBell() {
        let s = engine().status(at: at(8, 11, 45), lunch: .a)
        #expect(s.label == "A Lunch")
        #expect(s.nextBell == at(8, 11, 47))
    }

    @Test func afterDismissIsPassingUntilFifth() {
        let atBell = engine().status(at: at(8, 11, 47), lunch: .a)
        #expect(atBell.label == "Passing")
        #expect(atBell.nextBell == at(8, 11, 52))
    }

    @Test func bAndCHavePassingAfterAdvisory() {
        for lunch in [LunchGroup.b, .c] {
            let s = engine().status(at: at(8, 11, 25), lunch: lunch)
            #expect(s.label == "Passing")
            #expect(s.nextBell == at(8, 11, 28))
        }
    }

    @Test func bLunchIsSplitAroundLunch() {
        let e = engine()
        #expect(e.status(at: at(8, 11, 40), lunch: .b).nextBell == at(8, 11, 52))
        #expect(e.status(at: at(8, 12, 0), lunch: .b).label == "B Lunch")
        #expect(e.status(at: at(8, 12, 0), lunch: .b).nextBell == at(8, 12, 17))
        #expect(e.status(at: at(8, 12, 30), lunch: .b).label == "5th")
    }

    @Test func cLunchDismissesAtTwelveFortySeven() {
        let s = engine().status(at: at(8, 12, 30), lunch: .c)
        #expect(s.label == "C Lunch")
        #expect(s.nextBell == at(8, 12, 47))
    }

    @Test func everyoneMeetsAtSixth() {
        for lunch in LunchGroup.allCases {
            let s = engine().status(at: at(8, 12, 50), lunch: lunch)
            #expect(s.label == "Passing")
            #expect(s.nextBell == at(8, 12, 53))
        }
    }

    @Test func lastBellEndsTheDay() {
        let s = engine().status(at: at(8, 14, 35), lunch: .a)
        #expect(!s.inSession)
        #expect(s.label == nil)
        #expect(s.nextBell == nil)
    }

    @Test func finishedBlocksAreTheOnesAlreadyLeft() {
        let s = engine().status(at: at(8, 10, 0), lunch: .c)
        #expect(s.finishedBlocks.map(\.name) == ["1st", "2nd", "3rd"])
    }

    @Test func statusOnlyChangesAtBells() {
        // The menu re-renders only when the status changes, so it must stay equal between bells.
        let e = engine()
        #expect(e.status(at: at(8, 10, 0), lunch: .c) == e.status(at: at(8, 10, 1), lunch: .c))
        #expect(e.status(at: at(8, 10, 0), lunch: .c) != e.status(at: at(8, 10, 45), lunch: .c))
    }

    // MARK: Alternate schedules

    @Test func jamboreeALunchHasPassingBeforeFifth() {
        let e = engine(calendar: [assign("jamboree", "2026-10-09")])
        let s = e.status(at: at(9, 11, 18), lunch: .a)
        #expect(s.schedule?.name == "Jamboree")
        #expect(s.label == "Passing")
        #expect(s.nextBell == at(9, 11, 22))
    }

    @Test func jamboreeCLunchRunsIntoPassing() {
        let e = engine(calendar: [assign("jamboree", "2026-10-09")])
        #expect(e.status(at: at(9, 12, 20), lunch: .c).label == "C Lunch → Jamboree")
        #expect(e.status(at: at(9, 12, 55), lunch: .c).nextBell == at(9, 12, 59))
    }

    @Test func pepRallyTransitionAndRally() {
        let e = engine(calendar: [assign("pep-rally", "2026-10-07")])
        #expect(e.status(at: at(7, 10, 40), lunch: .b).label == "Transition to Field")
        #expect(e.status(at: at(7, 11, 0), lunch: .b).nextBell == at(7, 11, 18))
        #expect(e.status(at: at(7, 11, 20), lunch: .b).label == "Passing")
    }

    @Test func pepRallyCLunchDismissal() {
        let e = engine(calendar: [assign("pep-rally", "2026-10-07")])
        #expect(e.status(at: at(7, 12, 50), lunch: .c).nextBell == at(7, 12, 53))
        #expect(e.status(at: at(7, 12, 55), lunch: .c).nextBell == at(7, 12, 59))
    }

    // MARK: Looking ahead

    @Test func nextBellSkipsTheWeekend() {
        #expect(engine().nextBell(after: at(9, 15, 0), lunch: .a) == at(12, 7, 9))
    }

    @Test func nextBellSkipsNoSchoolDays() {
        let e = engine(calendar: [assign(nil, "2026-10-12", through: "2026-10-13")])
        #expect(e.nextBell(after: at(9, 15, 0), lunch: .a) == at(14, 7, 9))
    }

    // MARK: Formatting

    @Test func countdownFormats() {
        #expect(Countdown.format(299) == "4:59")
        #expect(Countdown.format(298.2) == "4:59")
        #expect(Countdown.format(723) == "12:03")
        #expect(Countdown.format(3723) == "1:02:03")
        #expect(Countdown.format(2 * 86_400 + 3 * 3600 + 5) == "2d 3h")
        #expect(Countdown.format(-5) == "0:00")
    }
}
