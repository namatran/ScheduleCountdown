import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
    }
}
