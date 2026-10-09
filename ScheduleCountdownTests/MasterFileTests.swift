import Foundation
import Testing
@testable import ScheduleCountdown

struct MasterFileTests {
    @Test func bundledScheduleLoads() {
        let master = MasterFile.bundled()
        #expect(master.defaultScheduleID == "normal")
        #expect(master.schedules.map(\.id) == ["normal", "jamboree", "pep-rally"])
        #expect(master.calendar.isEmpty)
    }

    @Test func blocksWithoutGroupsAreShared() throws {
        let normal = try #require(MasterFile.bundled().schedule(id: "normal"))
        let first = try #require(normal.blocks.first)
        #expect(first.groups == Set(LunchGroup.allCases))
    }

    @Test func roundTripsThroughJSON() throws {
        let master = MasterFile.bundled()
        let again = try MasterFile.decode(master.encoded())
        #expect(again == master)
    }

    @Test func sharedGroupsAreLeftOutWhenEncoding() throws {
        let block = Block(name: "1st", start: ClockTime(7, 15), end: ClockTime(8, 3))
        let json = try #require(String(data: JSONEncoder().encode(block), encoding: .utf8))
        #expect(!json.contains("groups"))
    }

    @Test func rejectsUnknownDefaultSchedule() {
        let json = #"{"version":1,"defaultScheduleID":"nope","schedules":[],"calendar":[]}"#
        #expect(throws: DecodingError.self) { try MasterFile.decode(Data(json.utf8)) }
    }

    @Test func rejectsBadTimes() {
        #expect(ClockTime("7:15") == ClockTime(7, 15))
        #expect(ClockTime("24:00") == nil)
        #expect(ClockTime("12:60") == nil)
        #expect(ClockTime("noon") == nil)
    }

    @Test func displaysTwelveHourTimes() {
        #expect(ClockTime(7, 9).display == "7:09")
        #expect(ClockTime(12, 53).display == "12:53")
        #expect(ClockTime(13, 41).display == "1:41")
    }

    @Test func blocksForLunchAreSortedAndFiltered() throws {
        let normal = try #require(MasterFile.bundled().schedule(id: "normal"))
        let names = normal.blocks(for: .b).map(\.name)
        #expect(names == ["1st", "2nd", "3rd", "4th", "Advisory", "5th", "B Lunch", "5th", "6th", "7th"])
    }
}
