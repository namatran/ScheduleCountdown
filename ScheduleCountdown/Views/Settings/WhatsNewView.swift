import SwiftUI

/// Settings → What's New: every release's notes from the bundled changelog, newest first.
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    private let changelog = Changelog.bundled()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(changelog.releases) { release in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(release.version).font(.headline)
                                if let date = release.date {
                                    // Changelog dates are calendar days, parsed as UTC midnight.
                                    Text(date.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: .gmt)))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            ForEach(release.notes, id: \.self) { note in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("•")
                                    Text(note).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 420, height: 420)
    }
}
