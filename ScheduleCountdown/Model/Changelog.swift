import Foundation

/// CHANGELOG.md, bundled with the app for Settings → What's New.
/// Each release is a `## <version>` heading (with ` — yyyy-MM-dd` once released) and `- ` bullets.
struct Changelog: Equatable {
    struct Release: Equatable, Identifiable {
        var version: String
        var date: Date?
        var notes: [String]
        var id: String { version }
    }

    var releases: [Release]

    init(markdown: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var releases: [Release] = []
        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("## ") {
                let parts = line.dropFirst(3).components(separatedBy: " — ")
                releases.append(Release(
                    version: parts[0].trimmingCharacters(in: .whitespaces),
                    date: parts.count > 1 ? dateFormatter.date(from: parts[1].trimmingCharacters(in: .whitespaces)) : nil,
                    notes: []))
            } else if !releases.isEmpty, line.hasPrefix("- ") {
                releases[releases.count - 1].notes.append(String(line.dropFirst(2)))
            } else if !releases.isEmpty, line.hasPrefix("  "), !releases[releases.count - 1].notes.isEmpty {
                // A bullet wrapped onto the next line.
                let index = releases[releases.count - 1].notes.count - 1
                releases[releases.count - 1].notes[index] += " " + line.trimmingCharacters(in: .whitespaces)
            }
        }
        self.releases = releases
    }

    static func bundled() -> Changelog {
        let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md")
        let markdown = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        return Changelog(markdown: markdown)
    }
}
