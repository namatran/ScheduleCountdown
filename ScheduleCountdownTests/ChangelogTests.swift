import Foundation
import Testing
@testable import ScheduleCountdown

struct ChangelogTests {
    @Test func parsesReleasesNewestFirst() {
        let changelog = Changelog(markdown: """
            # Changelog

            Intro text that isn't a release.

            ## 1.2.0

            - Unreleased change that wraps
              onto a second line.

            ## 1.1.0 — 2026-10-20

            - First change.
            - Second change.
            """)
        #expect(changelog.releases.map(\.version) == ["1.2.0", "1.1.0"])
        #expect(changelog.releases[0].date == nil)
        #expect(changelog.releases[0].notes == ["Unreleased change that wraps onto a second line."])
        #expect(changelog.releases[1].notes == ["First change.", "Second change."])

        let date = try? Date("2026-10-20T00:00:00Z", strategy: .iso8601)
        #expect(changelog.releases[1].date == date)
    }

    @Test func bundledChangelogCoversThisVersion() throws {
        let version = try #require(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
        let release = Changelog.bundled().releases.first { $0.version == version }
        #expect(release?.notes.isEmpty == false)
    }
}
