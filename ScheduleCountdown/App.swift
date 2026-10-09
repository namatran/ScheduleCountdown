import SwiftUI

@main
struct ScheduleCountdownApp: App {
    var body: some Scene {
        MenuBarExtra {
            Button("Quit") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "bell")
        }
        .menuBarExtraStyle(.menu)
    }
}
