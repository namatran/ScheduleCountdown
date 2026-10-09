import SwiftUI

@main
struct ScheduleCountdownApp: App {
    @State private var state: AppState

    init() {
        let state = AppState()
        // Don't spin up the clock or hit the network while hosting unit tests.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            state.start()
        }
        _state = State(initialValue: state)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(state)
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(state)
        }
    }
}
