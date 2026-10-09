import AppKit

/// Sparkle can't update an app outside Applications, or one macOS runs translocated (from a
/// read-only copy) because it was opened from Downloads or a disk image. So on launch, offer
/// to move it into Applications and relaunch from there.
enum AppMover {
    /// Asks, and if the student agrees, moves the app and quits so the moved copy relaunches.
    /// Returns true when the app is about to quit.
    @MainActor
    static func moveIfNeeded() -> Bool {
        #if DEBUG
        return false  // Xcode runs builds from DerivedData.
        #else
        let bundleURL = Bundle.main.bundleURL
        guard !isInApplications(bundleURL) else { return false }

        let alert = NSAlert()
        alert.messageText = "Move to Applications?"
        alert.informativeText = "ScheduleCountdown needs to be in your Applications folder to update itself."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        // A menu bar app isn't active, so keep the alert above other apps' windows.
        NSApp.activate()
        alert.window.level = .floating
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        do {
            try move(bundleURL)
            return true
        } catch {
            let failure = NSAlert(error: error)
            failure.messageText = "Couldn't move ScheduleCountdown to Applications"
            failure.window.level = .floating
            failure.runModal()
            return false
        }
        #endif
    }

    static func isInApplications(_ url: URL,
                                 home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let path = url.standardizedFileURL.path
        let folders = ["/Applications", home.appendingPathComponent("Applications").standardizedFileURL.path]
        return folders.contains { path.hasPrefix($0 + "/") }
    }

    /// /Applications, or the student's own ~/Applications when it isn't writable (managed Macs),
    /// so moving never needs an admin password.
    static func destinationFolder(systemIsWritable: Bool = FileManager.default.isWritableFile(atPath: "/Applications"),
                                  home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        systemIsWritable
            ? URL(fileURLWithPath: "/Applications", isDirectory: true)
            : home.appendingPathComponent("Applications", isDirectory: true)
    }

    @MainActor
    private static func move(_ bundleURL: URL) throws {
        let fileManager = FileManager.default
        let original = originalURL(of: bundleURL)
        let folder = destinationFolder()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(bundleURL.lastPathComponent)

        if fileManager.fileExists(atPath: destination.path) {
            // An older copy, like 1.0.0. Quit it if it's running, and keep it in the Trash.
            quitRunningCopy(at: destination)
            try fileManager.trashItem(at: destination, resultingItemURL: nil)
        }
        try fileManager.copyItem(at: bundleURL, to: destination)
        // This copy already passed Gatekeeper; without quarantine macOS won't translocate it.
        run("/usr/bin/xattr", ["-d", "-r", "com.apple.quarantine", destination.path])

        let values = try? original.resourceValues(forKeys: [.volumeIsReadOnlyKey, .volumeURLKey])
        let diskImage = values?.volumeIsReadOnly == true ? values?.volume : nil
        if diskImage == nil {
            try? fileManager.trashItem(at: original, resultingItemURL: nil)
        }
        relaunch(destination, ejecting: diskImage)
    }

    /// Where a translocated app really is (Downloads, a disk image, …). Other URLs are returned as is.
    private static func originalURL(of url: URL) -> URL {
        guard url.path.contains("/AppTranslocation/"),
              let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let symbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL")
        else { return url }
        typealias Function = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        let original = unsafeBitCast(symbol, to: Function.self)(url as CFURL, nil)
        return original.map { $0.takeRetainedValue() as URL } ?? url
    }

    @MainActor
    private static func quitRunningCopy(at url: URL) {
        guard let id = Bundle.main.bundleIdentifier else { return }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: id)
        where app.bundleURL?.standardizedFileURL == url.standardizedFileURL {
            app.terminate()
            let deadline = Date().addingTimeInterval(5)
            while !app.isTerminated, Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
        }
    }

    /// Waits for this process to exit, ejects the disk image it came from, and opens the moved copy.
    @MainActor
    private static func relaunch(_ app: URL, ejecting diskImage: URL?) {
        let script = """
            while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done
            [ -n "$3" ] && /usr/bin/hdiutil detach "$3" -quiet
            /usr/bin/open "$2"
            """
        run("/bin/sh", ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier),
                        app.path, diskImage?.path ?? ""], wait: false)
        NSApp.terminate(nil)
    }

    private static func run(_ tool: String, _ arguments: [String], wait: Bool = true) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        if wait { process.waitUntilExit() }
    }
}
