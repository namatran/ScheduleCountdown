import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            if state.editorMode {
                SchedulesTab()
                    .tabItem { Label("Schedules", systemImage: "list.bullet.rectangle") }
            }
        }
    }
}
