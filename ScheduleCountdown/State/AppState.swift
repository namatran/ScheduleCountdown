import Foundation
import Observation

/// App-wide state: the ticking clock, user settings, and the status derived from them.
@MainActor @Observable
final class AppState {
    let store: ScheduleStore
    private(set) var now = Date()

    var lunch: LunchGroup {
        didSet {
            defaults.set(lunch.rawValue, forKey: Keys.lunch)
            refreshMenuStatus()
        }
    }
    var showCountdownOutsideSchool: Bool {
        didSet { defaults.set(showCountdownOutsideSchool, forKey: Keys.outsideSchool) }
    }
    var editorMode: Bool {
        didSet {
            defaults.set(editorMode, forKey: Keys.editorMode)
            refreshMenuStatus()
        }
    }
    /// What the dropdown shows. Unlike `status`, it's only reassigned when it changes (at a bell,
    /// not every second), because re-rendering the menu rebuilds it and closes open submenus.
    private(set) var menuStatus = DayStatus()
    /// Set for this launch when Settings is opened with ⌥ held, so the Editor mode switch appears.
    var revealEditorToggle = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clockOffset: TimeInterval
    @ObservationIgnored private var timer: Timer?

    private enum Keys {
        static let lunch = "lunch"
        static let outsideSchool = "showCountdownOutsideSchool"
        static let editorMode = "editorMode"
    }

    init(store: ScheduleStore? = nil, defaults: UserDefaults = .standard) {
        self.store = store ?? ScheduleStore()
        self.defaults = defaults
        lunch = defaults.string(forKey: Keys.lunch).flatMap(LunchGroup.init) ?? .a
        showCountdownOutsideSchool = defaults.bool(forKey: Keys.outsideSchool)
        editorMode = defaults.bool(forKey: Keys.editorMode)
        clockOffset = Self.fakeClockOffset()
        now = Date().addingTimeInterval(clockOffset)
        refreshMenuStatus()
    }

    /// Editors see their draft live; everyone else follows the published master.
    var master: MasterFile { editorMode ? store.draft : store.published }
    var engine: ScheduleEngine { ScheduleEngine(master: master) }
    var status: DayStatus { engine.status(at: now, lunch: lunch) }

    /// Countdown text for the menu bar, or nil to show just the bell icon.
    var menuBarTitle: String? {
        let status = status
        if status.inSession, let next = status.nextBell {
            return Countdown.format(next.timeIntervalSince(now))
        }
        if showCountdownOutsideSchool, let next = engine.nextBell(after: now, lunch: lunch) {
            return Countdown.format(next.timeIntervalSince(now))
        }
        return nil
    }

    func start() {
        guard timer == nil else { return }
        // Tick on whole seconds so the countdown changes in step with the clock.
        let firstTick = Date(timeIntervalSinceReferenceDate:
            (Date().timeIntervalSinceReferenceDate + 1).rounded(.down))
        let timer = Timer(fire: firstTick, interval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.05
        // .common keeps it ticking while the menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        store.startAutoRefresh()
    }

    private func tick() {
        now = Date().addingTimeInterval(clockOffset)
        // Also picks up schedule downloads and editor changes within a second.
        refreshMenuStatus()
    }

    private func refreshMenuStatus() {
        let status = status
        if status != menuStatus { menuStatus = status }
    }

    /// Debug aid: `SC_FAKE_NOW="2026-10-09 11:45"` makes the app run as if it were that moment.
    private static func fakeClockOffset() -> TimeInterval {
        guard let raw = ProcessInfo.processInfo.environment["SC_FAKE_NOW"] else { return 0 }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard let fake = formatter.date(from: raw) else { return 0 }
        return fake.timeIntervalSinceNow.rounded()
    }
}
