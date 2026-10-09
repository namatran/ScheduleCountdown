import SwiftUI

/// Editor mode: the library of reusable named schedules.
struct SchedulesTab: View {
    @Environment(AppState.self) private var state
    @State private var selection: String?

    var body: some View {
        @Bindable var store = state.store
        let draft = store.draft

        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                List(selection: $selection) {
                    ForEach(draft.schedules) { schedule in
                        HStack {
                            Text(schedule.name)
                            Spacer()
                            if schedule.id == draft.defaultScheduleID {
                                Text("Default").font(.caption).foregroundStyle(.secondary)
                            }
                            if !schedule.problems().isEmpty {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                            }
                        }
                        .tag(schedule.id)
                    }
                }
                Divider()
                HStack(spacing: 4) {
                    Button { add() } label: { Image(systemName: "plus") }
                        .help("New schedule")
                    Button { remove() } label: { Image(systemName: "minus") }
                        .help(removeHelp)
                        .disabled(!canRemove)
                    Spacer()
                    Button("Duplicate", action: duplicate)
                        .disabled(selection == nil)
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(minWidth: 170, idealWidth: 190, maxWidth: 240)

            Group {
                if let index = draft.schedules.firstIndex(where: { $0.id == selection }) {
                    ScheduleEditor(
                        schedule: $store.draft.schedules[index],
                        isDefault: draft.schedules[index].id == draft.defaultScheduleID,
                        makeDefault: { store.draft.defaultScheduleID = draft.schedules[index].id }
                    )
                } else {
                    Text("Select a schedule").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 600)
        }
        .frame(width: 880, height: 560)
        .onAppear { if selection == nil { selection = draft.defaultScheduleID } }
    }

    private var canRemove: Bool {
        guard let selection else { return false }
        let draft = state.store.draft
        return selection != draft.defaultScheduleID
            && !draft.calendar.contains { $0.scheduleID == selection }
    }

    private var removeHelp: String {
        guard let selection else { return "Delete schedule" }
        if selection == state.store.draft.defaultScheduleID { return "The default schedule can't be deleted" }
        if !canRemove { return "Remove this schedule from the Calendar first" }
        return "Delete schedule"
    }

    private static func newID() -> String {
        "schedule-" + UUID().uuidString.prefix(8).lowercased()
    }

    private func add() {
        let schedule = Schedule(id: Self.newID(), name: "New Schedule", blocks: [
            Block(name: "1st", start: ClockTime(7, 15), end: ClockTime(8, 0)),
        ])
        state.store.draft.schedules.append(schedule)
        selection = schedule.id
    }

    private func duplicate() {
        guard let original = state.store.draft.schedules.first(where: { $0.id == selection }) else { return }
        var copy = original
        copy.id = Self.newID()
        copy.name = "\(original.name) Copy"
        state.store.draft.schedules.append(copy)
        selection = copy.id
    }

    private func remove() {
        guard canRemove, let selection else { return }
        state.store.draft.schedules.removeAll { $0.id == selection }
        self.selection = state.store.draft.defaultScheduleID
    }
}

private struct ScheduleEditor: View {
    @Binding var schedule: Schedule
    let isDefault: Bool
    let makeDefault: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Name", text: $schedule.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .frame(maxWidth: 260)
                Spacer()
                if isDefault {
                    Text("Used on every weekday without a Calendar entry")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Make Default", action: makeDefault)
                }
            }

            GroupBox("One-off bells") {
                VStack(alignment: .leading) {
                    ForEach($schedule.bells) { $bell in
                        HStack {
                            TextField("Name", text: $bell.name).frame(width: 180)
                            TimeField(time: $bell.time)
                            Spacer()
                            deleteButton { schedule.bells.removeAll { $0.id == bell.id } }
                        }
                    }
                    Button("Add Bell") {
                        schedule.bells.append(Bell(name: "Release", time: ClockTime(7, 9)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Blocks") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Name").frame(width: 170, alignment: .leading)
                        Text("Start").frame(width: 70, alignment: .leading)
                        Text("End").frame(width: 70, alignment: .leading)
                        Text("Early dismiss").frame(width: 120, alignment: .leading)
                        Text("Lunches")
                    }
                    .font(.caption).foregroundStyle(.secondary)

                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach($schedule.blocks) { $block in
                                BlockRow(block: $block) {
                                    schedule.blocks.removeAll { $0.id == block.id }
                                }
                            }
                        }
                    }

                    HStack {
                        Button("Add Block", action: addBlock)
                        Button("Sort by Start Time") {
                            schedule.blocks.sort { ($0.start, $0.end) < ($1.start, $1.end) }
                        }
                    }
                }
            }

            let problems = schedule.problems()
            if !problems.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(problems, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
            }
        }
        .padding()
    }

    private func addBlock() {
        // Start after a 6-minute passing period following the latest block.
        let start = schedule.blocks.map(\.end).max()?.adding(minutes: 6) ?? ClockTime(7, 15)
        schedule.blocks.append(Block(name: "New Block", start: start, end: start.adding(minutes: 48)))
    }
}

private struct BlockRow: View {
    @Binding var block: Block
    let onDelete: () -> Void

    var body: some View {
        HStack {
            TextField("Name", text: $block.name).frame(width: 170)
            TimeField(time: $block.start).frame(width: 70)
            TimeField(time: $block.end).frame(width: 70)
            HStack(spacing: 4) {
                Toggle("", isOn: hasDismiss).labelsHidden()
                if block.dismiss != nil {
                    TimeField(time: dismissTime)
                }
            }
            .frame(width: 120, alignment: .leading)
            ForEach(LunchGroup.allCases) { lunch in
                Toggle(lunch.rawValue, isOn: groupBinding(lunch))
            }
            Spacer()
            deleteButton(action: onDelete)
        }
    }

    private var hasDismiss: Binding<Bool> {
        Binding(
            get: { block.dismiss != nil },
            set: { on in
                block.dismiss = on ? max(block.start.adding(minutes: 1), block.end.adding(minutes: -5)) : nil
            }
        )
    }

    private var dismissTime: Binding<ClockTime> {
        Binding(get: { block.dismiss ?? block.end }, set: { block.dismiss = $0 })
    }

    private func groupBinding(_ lunch: LunchGroup) -> Binding<Bool> {
        Binding(
            get: { block.groups.contains(lunch) },
            set: { on in
                if on { block.groups.insert(lunch) } else { block.groups.remove(lunch) }
            }
        )
    }
}

private func deleteButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: "trash")
    }
    .buttonStyle(.borderless)
    .help("Delete")
}
