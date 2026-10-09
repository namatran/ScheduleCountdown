import SwiftUI

/// Editor mode: which days use an alternate schedule, and which days have no school.
struct CalendarTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var store = state.store
        let draft = store.draft
        let defaultName = draft.schedule(id: draft.defaultScheduleID)?.name ?? "the default schedule"

        VStack(alignment: .leading, spacing: 12) {
            Text("Weekdays not listed here use \(defaultName). Weekends have no school unless listed.")
                .foregroundStyle(.secondary)

            if draft.calendar.isEmpty {
                Text("No days assigned yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("From").frame(width: 110, alignment: .leading)
                    Text("To").frame(width: 110, alignment: .leading)
                    Text("Schedule").frame(width: 170, alignment: .leading)
                    Text("Note")
                }
                .font(.caption).foregroundStyle(.secondary)

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach($store.draft.calendar) { $entry in
                            EntryRow(entry: $entry, schedules: draft.schedules) {
                                store.draft.calendar.removeAll { $0.id == entry.id }
                            }
                        }
                    }
                }
            }

            HStack {
                Button("Add Alternate Day") { add(scheduleID: firstAlternateID) }
                Button("Add No-School Days") { add(scheduleID: nil) }
                Spacer()
                Button("Sort by Date", action: sort)
                    .disabled(draft.calendar.count < 2)
            }
        }
        .padding()
        .frame(width: 720, height: 480)
        .onAppear(perform: sort)
    }

    private var firstAlternateID: String {
        let draft = state.store.draft
        return draft.schedules.first { $0.id != draft.defaultScheduleID }?.id ?? draft.defaultScheduleID
    }

    private func add(scheduleID: String?) {
        let today = DayDate(state.now, calendar: .current)
        state.store.draft.calendar.append(CalendarEntry(start: today, end: today, scheduleID: scheduleID))
    }

    private func sort() {
        state.store.draft.calendar.sort { ($0.start, $0.end) < ($1.start, $1.end) }
    }
}

private struct EntryRow: View {
    @Binding var entry: CalendarEntry
    let schedules: [Schedule]
    let onDelete: () -> Void

    var body: some View {
        HStack {
            DayField(day: Binding(
                get: { entry.start },
                set: { start in
                    entry.start = start
                    if entry.end < start { entry.end = start }
                }
            ))
            .frame(width: 110)
            DayField(day: $entry.end, minimum: entry.start)
                .frame(width: 110)
            Picker("", selection: $entry.scheduleID) {
                Text("No School").tag(String?.none)
                Divider()
                ForEach(schedules) { Text($0.name).tag(Optional($0.id)) }
            }
            .labelsHidden()
            .frame(width: 170)
            TextField("e.g. Homecoming", text: Binding(
                get: { entry.note ?? "" },
                set: { entry.note = $0.isEmpty ? nil : $0 }
            ))
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete")
        }
    }
}
