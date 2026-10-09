import SwiftUI

@main
struct ScheduleCountdownApp: App {
    @State private var state: AppState
    @State private var updater: AppUpdater

    init() {
        let state = AppState()
        let updater = AppUpdater()
        // Don't spin up the clock or hit the network while hosting unit tests.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            state.start()
            // After launch finishes, so the alert can show. Sparkle waits: it can't update
            // a copy that's about to move.
            DispatchQueue.main.async {
                if !AppMover.moveIfNeeded() { updater.start() }
            }
        }
        _state = State(initialValue: state)
        _updater = State(initialValue: updater)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(state)
                .environment(updater)
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(state)
                .environment(updater)
        }
    }
}
