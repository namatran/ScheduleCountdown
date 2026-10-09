import SwiftUI

struct MenuBarLabel: View {
    let state: AppState

    var body: some View {
        if let title = state.menuBarTitle {
            Text(title).monospacedDigit()
        } else {
            Image(systemName: "bell")
        }
    }
}

/// The dropdown: current period → today's blocks → lunch picker → schedule name → app actions.
struct MenuContent: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var state = state
        let status = state.menuStatus

        Text(headline(status))

        if !status.blocks.isEmpty {
            Divider()
            ForEach(status.blocks) { block in
                blockRow(block, status: status)
            }
        }

        Divider()
        Picker("Lunch", selection: $state.lunch) {
            ForEach(LunchGroup.allCases) { Text($0.title).tag($0) }
        }

        Divider()
        Text(status.schedule.map { "\($0.name) Schedule" } ?? "No School Today")

        Divider()
        Button(state.store.isChecking ? "Checking…" : "Check for Updates") {
            Task { await state.store.checkForUpdates() }
        }
        .disabled(state.store.remoteURL == nil || state.store.isChecking)
        Button("Settings…", action: showSettings)
            .keyboardShortcut(",")
        Button("Quit ScheduleCountdown") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func headline(_ status: DayStatus) -> String {
        if let block = status.currentBlock {
            return "\(block.name) — until \(block.effectiveEnd.display)"
        }
        if status.inSession {
            if let next = status.nextBlock { return "Passing — \(next.name) at \(next.start.display)" }
            return "Passing"
        }
        if status.schedule == nil { return "No school" }
        return status.nextBell == nil ? "School's out" : "Before school"
    }

    /// Finished blocks are greyed out; the current one is marked ▶, the next one →.
    @ViewBuilder
    private func blockRow(_ block: Block, status: DayStatus) -> some View {
        let times = "\(block.start.display)–\(block.end.display)"
            + (block.dismiss.map { " (out \($0.display))" } ?? "")

        if block.id == status.currentBlock?.id {
            Button("▶  \(block.name)   \(times)") {}
        } else if block.id == status.nextBlock?.id {
            Button("→  \(block.name)   \(times)") {}
        } else if status.finishedBlocks.contains(block) {
            Text("     \(block.name)   \(times)")
        } else {
            Button("     \(block.name)   \(times)") {}
        }
    }

    private func showSettings() {
        if NSEvent.modifierFlags.contains(.option) {
            state.revealEditorToggle = true
        }
        // Menu bar apps aren't active by default, so the window would open behind others.
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        DispatchQueue.main.async {
            NSApp.windows
                .first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }?
                .makeKeyAndOrderFront(nil)
        }
    }
}
