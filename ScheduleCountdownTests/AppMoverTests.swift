import Foundation
import Testing
@testable import ScheduleCountdown

struct AppMoverTests {
    let home = URL(fileURLWithPath: "/Users/student", isDirectory: true)

    private func inApplications(_ path: String) -> Bool {
        AppMover.isInApplications(URL(fileURLWithPath: path), home: home)
    }

    @Test func applicationsFoldersNeedNoMove() {
        #expect(inApplications("/Applications/ScheduleCountdown.app"))
        #expect(inApplications("/Applications/School/ScheduleCountdown.app"))
        #expect(inApplications("/Users/student/Applications/ScheduleCountdown.app"))
    }

    @Test func elsewhereNeedsMove() {
        #expect(!inApplications("/Users/student/Downloads/ScheduleCountdown.app"))
        #expect(!inApplications("/Volumes/ScheduleCountdown/ScheduleCountdown.app"))
        #expect(!inApplications(
            "/private/var/folders/xy/T/AppTranslocation/0BE8/d/ScheduleCountdown.app"))
        #expect(!inApplications("/ApplicationsOld/ScheduleCountdown.app"))
    }

    @Test func fallsBackToHomeApplicationsWhenNotWritable() {
        #expect(AppMover.destinationFolder(systemIsWritable: true, home: home).path == "/Applications")
        #expect(AppMover.destinationFolder(systemIsWritable: false, home: home).path
            == "/Users/student/Applications")
    }
}
