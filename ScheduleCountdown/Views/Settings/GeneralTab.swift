import ServiceManagement
import SwiftUI

struct GeneralTab: View {
    @Environment(AppState.self) private var state
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?
    @State private var exportError: String?

    var body: some View {
        @Bindable var state = state

        Form {
            Section {
                Picker("Lunch", selection: $state.lunch) {
                    ForEach(LunchGroup.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchAtLoginError {
                    Text(launchAtLoginError).font(.caption).foregroundStyle(.red)
                }

                Toggle("Show countdown outside school hours", isOn: $state.showCountdownOutsideSchool)
                Text("When off, the menu bar shows a bell before and after school and on days off.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Master schedule") {
                LabeledContent("Last updated", value: formattedUpdatedAt(state.store.published.updatedAt))
                LabeledContent("Last checked", value: state.store.lastChecked
                    .map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                if let error = state.store.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                if state.store.remoteURL == nil {
                    Text("No online schedule is set up yet, so the built-in schedule is used.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Check for Updates") {
                    Task { await state.store.checkForUpdates() }
                }
                .disabled(state.store.remoteURL == nil || state.store.isChecking)
            }

            if state.revealEditorToggle || state.editorMode {
                editorSection
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var editorSection: some View {
        @Bindable var state = state

        Section("Editor") {
            Toggle("Editor mode", isOn: $state.editorMode)
            Text("Edit schedules and the calendar on this Mac, then export the master file and push it so everyone gets it. While on, this Mac follows your draft instead of the published schedule.")
                .font(.caption).foregroundStyle(.secondary)

            if state.editorMode {
                HStack {
                    Button("Export Master File…", action: export)
                    Button("Discard Draft Changes", role: .destructive) { state.store.discardDraft() }
                        .disabled(!state.store.draftHasChanges)
                }
                Text(state.store.draftHasChanges ? "Draft has unpublished changes." : "Draft matches the published schedule.")
                    .font(.caption).foregroundStyle(.secondary)
                if let exportError {
                    Text(exportError).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "schedule.json"
        panel.allowedContentTypes = [.json]
        panel.message = "Save over ScheduleCountdown/Resources/schedule.json in the repo, then commit and push."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try state.store.exportDraft(to: url)
            exportError = nil
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func formattedUpdatedAt(_ raw: String?) -> String {
        guard let raw, let date = ISO8601DateFormatter().date(from: raw) else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
