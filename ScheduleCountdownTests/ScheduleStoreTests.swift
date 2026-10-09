import Foundation
import Testing
@testable import ScheduleCountdown

@MainActor
struct ScheduleStoreTests {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScheduleStoreTests-\(UUID().uuidString)", isDirectory: true)

    private func remoteFile(_ master: MasterFile) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("remote.json")
        try master.encoded().write(to: url)
        return url
    }

    private func pepRallyTomorrow() -> MasterFile {
        var master = MasterFile.bundled()
        master.calendar = [CalendarEntry(start: DayDate("2026-10-09")!, end: DayDate("2026-10-09")!,
                                         scheduleID: "pep-rally")]
        return master
    }

    @Test func startsFromTheBundledCopy() {
        let store = ScheduleStore(remoteURL: nil, directory: directory)
        #expect(store.published == MasterFile.bundled())
        #expect(!store.draftHasChanges)
    }

    @Test func downloadsAndCachesTheMaster() async throws {
        let remote = pepRallyTomorrow()
        let store = ScheduleStore(remoteURL: try remoteFile(remote), directory: directory)
        #expect(await store.checkForUpdates() == .updated)
        #expect(store.lastError == nil)
        #expect(store.published == remote)
        #expect(await store.checkForUpdates() == .upToDate)

        // A fresh launch with no network uses the cached copy.
        let offline = ScheduleStore(remoteURL: nil, directory: directory)
        #expect(offline.published == remote)
    }

    @Test func keepsLastGoodCopyWhenRemoteIsBroken() async throws {
        let url = try remoteFile(MasterFile.bundled())
        try Data("not json".utf8).write(to: url)
        let store = ScheduleStore(remoteURL: url, directory: directory)
        guard case .failed = await store.checkForUpdates() else {
            Issue.record("expected the check to fail"); return
        }
        #expect(store.lastError != nil)
        #expect(store.published == MasterFile.bundled())
    }

    @Test func skipsCheckWithoutRemote() async {
        let store = ScheduleStore(remoteURL: nil, directory: directory)
        #expect(await store.checkForUpdates() == nil)
    }

    @Test func draftPersistsAndCanBeDiscarded() {
        let store = ScheduleStore(remoteURL: nil, directory: directory)
        store.draft.schedules[0].name = "Edited"
        #expect(store.draftHasChanges)
        #expect(ScheduleStore(remoteURL: nil, directory: directory).draft.schedules[0].name == "Edited")

        store.discardDraft()
        #expect(!store.draftHasChanges)
    }

    @Test func exportWritesALoadableMaster() throws {
        let store = ScheduleStore(remoteURL: nil, directory: directory)
        store.draft.calendar = pepRallyTomorrow().calendar
        let url = directory.appendingPathComponent("schedule.json")
        try store.exportDraft(to: url)
        let exported = try MasterFile.decode(Data(contentsOf: url))
        #expect(exported.calendar == store.draft.calendar)
        #expect(exported.updatedAt != nil)
    }
}
