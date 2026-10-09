import Foundation

/// The whole shared ("universal") schedule: every named schedule plus which days use them.
/// This is exactly what lives in `schedule.json`.
struct MasterFile: Codable, Equatable {
    var version: Int = 1
    var updatedAt: String?
    var defaultScheduleID: String
    var schedules: [Schedule]
    var calendar: [CalendarEntry]

    func schedule(id: String) -> Schedule? {
        schedules.first { $0.id == id }
    }

    static func decode(_ data: Data) throws -> MasterFile {
        let master = try JSONDecoder().decode(MasterFile.self, from: data)
        guard master.schedule(id: master.defaultScheduleID) != nil else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "defaultScheduleID '\(master.defaultScheduleID)' doesn't match any schedule"
            ))
        }
        return master
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// The copy shipped inside the app; used on first launch and whenever the network can't be reached.
    static func bundled() -> MasterFile {
        guard let url = Bundle.main.url(forResource: "schedule", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let master = try? decode(data)
        else { fatalError("Bundled schedule.json is missing or invalid") }
        return master
    }
}

enum LunchGroup: String, Codable, CaseIterable, Identifiable {
    case a = "A", b = "B", c = "C"

    var id: String { rawValue }
    var title: String { "\(rawValue) Lunch" }
}

struct Schedule: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    /// One-off bells that aren't the start or end of a block, like the 7:09 release bell.
    var bells: [Bell] = []
    var blocks: [Block]

    /// Blocks this lunch group actually sits through, in time order.
    func blocks(for lunch: LunchGroup) -> [Block] {
        blocks.filter { $0.groups.contains(lunch) }.sorted { $0.start < $1.start }
    }

    /// Mistakes worth flagging in the editor, e.g. overlapping blocks for the same lunch.
    func problems() -> [String] {
        var problems: [String] = []
        for block in blocks {
            if block.end <= block.start {
                problems.append("\(block.name) (\(block.start.display)) ends before it starts.")
            }
            if let dismiss = block.dismiss, !(block.start < dismiss && dismiss <= block.end) {
                problems.append("\(block.name) (\(block.start.display)) dismisses outside its own time.")
            }
            if block.groups.isEmpty {
                problems.append("\(block.name) (\(block.start.display)) isn't assigned to any lunch.")
            }
        }
        for lunch in LunchGroup.allCases {
            let sorted = blocks(for: lunch)
            for (earlier, later) in zip(sorted, sorted.dropFirst()) where earlier.end > later.start {
                problems.append("\(lunch.title): \(earlier.name) overlaps \(later.name).")
            }
        }
        return problems
    }
}

struct Bell: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var time: ClockTime

    private enum CodingKeys: String, CodingKey { case name, time }
}

struct Block: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var start: ClockTime
    var end: ClockTime
    /// Bell that lets students go before the official end (e.g. "Students dismiss at 11:47").
    var dismiss: ClockTime?
    var groups: Set<LunchGroup> = Set(LunchGroup.allCases)

    /// When you actually leave: the dismiss bell if there is one, otherwise the end.
    var effectiveEnd: ClockTime { dismiss ?? end }

    init(name: String, start: ClockTime, end: ClockTime, dismiss: ClockTime? = nil,
         groups: Set<LunchGroup> = Set(LunchGroup.allCases)) {
        self.name = name
        self.start = start
        self.end = end
        self.dismiss = dismiss
        self.groups = groups
    }

    private enum CodingKeys: String, CodingKey { case name, start, end, dismiss, groups }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        start = try c.decode(ClockTime.self, forKey: .start)
        end = try c.decode(ClockTime.self, forKey: .end)
        dismiss = try c.decodeIfPresent(ClockTime.self, forKey: .dismiss)
        // Leaving out "groups" means the block is shared by every lunch.
        groups = try c.decodeIfPresent(Set<LunchGroup>.self, forKey: .groups) ?? Set(LunchGroup.allCases)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
        try c.encodeIfPresent(dismiss, forKey: .dismiss)
        if groups != Set(LunchGroup.allCases) {
            try c.encode(LunchGroup.allCases.filter(groups.contains), forKey: .groups)
        }
    }
}

/// Assigns a day (or a range of days) to a schedule. `scheduleID == nil` means no school.
struct CalendarEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    var start: DayDate
    var end: DayDate
    var scheduleID: String?
    var note: String?

    private enum CodingKeys: String, CodingKey { case start, end, scheduleID, note }

    func contains(_ day: DayDate) -> Bool { start <= day && day <= end }
}

// The `id`s only exist so SwiftUI lists can track rows; they never hit the JSON,
// so two copies of the same schedule should compare equal regardless of them.
extension Bell {
    static func == (lhs: Bell, rhs: Bell) -> Bool {
        lhs.name == rhs.name && lhs.time == rhs.time
    }
}

extension Block {
    static func == (lhs: Block, rhs: Block) -> Bool {
        lhs.name == rhs.name && lhs.start == rhs.start && lhs.end == rhs.end
            && lhs.dismiss == rhs.dismiss && lhs.groups == rhs.groups
    }
}

extension CalendarEntry {
    static func == (lhs: CalendarEntry, rhs: CalendarEntry) -> Bool {
        lhs.start == rhs.start && lhs.end == rhs.end
            && lhs.scheduleID == rhs.scheduleID && lhs.note == rhs.note
    }
}
