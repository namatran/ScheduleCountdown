import SwiftUI

/// Hour-and-minute picker bound to a `ClockTime`.
struct TimeField: View {
    @Binding var time: ClockTime

    var body: some View {
        DatePicker("", selection: Binding(
            get: { time.date(on: Date(), calendar: .current) },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                time = ClockTime(c.hour ?? 0, c.minute ?? 0)
            }
        ), displayedComponents: .hourAndMinute)
        .labelsHidden()
        .datePickerStyle(.field)
    }
}

/// Date picker bound to a `DayDate`.
struct DayField: View {
    @Binding var day: DayDate
    var minimum: DayDate?

    var body: some View {
        let binding = Binding(
            get: { day.date(calendar: .current) },
            set: { day = DayDate($0, calendar: .current) }
        )
        if let minimum {
            DatePicker("", selection: binding, in: minimum.date(calendar: .current)...,
                       displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.field)
        } else {
            DatePicker("", selection: binding, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.field)
        }
    }
}
