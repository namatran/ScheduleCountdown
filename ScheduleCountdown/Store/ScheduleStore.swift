import AppKit
import Foundation
import Observation

/// Owns the schedule data: the shared master (bundled → cached → remote) and the editor's draft.
@MainActor @Observable
final class ScheduleStore {
    /// The universal schedule everyone follows.
    private(set) var published: MasterFile
    /// Editor mode's working copy. Saved on every change; only goes public when exported and pushed.
    var draft: MasterFile {
        didSet { save(draft, to: draftURL) }
    }
    private(set) var lastChecked: Date?
    private(set) var lastError: String?
    private(set) var isChecking = false

    let remoteURL: URL?
    private let cacheURL: URL
    private let draftURL: URL
    private var refreshTask: Task<Void, Never>?

    static let refreshInterval: TimeInterval = 6 * 3600

    init(remoteURL: URL? = ScheduleStore.configuredRemoteURL,
         directory: URL = ScheduleStore.defaultDirectory) {
        self.remoteURL = remoteURL
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cacheURL = directory.appendingPathComponent("master-cache.json")
        draftURL = directory.appendingPathComponent("editor-draft.json")

        let published = Self.load(cacheURL) ?? MasterFile.bundled()
        self.published = published
        self.draft = Self.load(draftURL) ?? published
    }

    /// `SC_REMOTE_URL` (for testing) or the `ScheduleRemoteURL` Info.plist key. Empty = offline only.
    nonisolated static var configuredRemoteURL: URL? {
        let raw = ProcessInfo.processInfo.environment["SC_REMOTE_URL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "ScheduleRemoteURL") as? String
            ?? ""
        return raw.isEmpty ? nil : URL(string: raw)
    }

    nonisolated static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScheduleCountdown", isDirectory: true)
    }

    /// Checks now, then every 6 hours, and again after the Mac wakes if a check is overdue.
    func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkForUpdates()
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let overdue = self.lastChecked.map { Date().timeIntervalSince($0) > Self.refreshInterval } ?? true
                if overdue { await self.checkForUpdates() }
            }
        }
    }

    /// Downloads the master file. On any failure the last good copy stays in use.
    func checkForUpdates() async {
        guard let remoteURL, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let request = URLRequest(url: remoteURL, cachePolicy: .reloadIgnoringLocalCacheData,
                                     timeoutInterval: 15)
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            let master = try MasterFile.decode(data)
            published = master
            save(master, to: cacheURL)
            lastError = nil
        } catch {
            lastError = (error as? DecodingError).map { _ in "The master schedule file is invalid." }
                ?? error.localizedDescription
        }
        lastChecked = Date()
    }

    var draftHasChanges: Bool {
        var a = draft, b = published
        a.updatedAt = nil
        b.updatedAt = nil
        return a != b
    }

    func discardDraft() {
        draft = published
    }

    /// Writes the draft as the new master file (stamped with the current time).
    func exportDraft(to url: URL) throws {
        draft.updatedAt = ISO8601DateFormatter().string(from: Date())
        try draft.encoded().write(to: url, options: .atomic)
    }

    private func save(_ master: MasterFile, to url: URL) {
        try? master.encoded().write(to: url, options: .atomic)
    }

    private static func load(_ url: URL) -> MasterFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? MasterFile.decode(data)
    }
}
