import AppKit
import Combine
import Sparkle

/// App self-updates through Sparkle. The feed and EdDSA public key come from Info.plist
/// (`SUFeedURL`, `SUPublicEDKey`); background checks are on via `SUEnableAutomaticChecks`.
@Observable
final class AppUpdater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private(set) var canCheck = false
    private(set) var isChecking = false
    /// The version waiting to be installed, e.g. "1.2.0". Cleared when the student skips it.
    private(set) var availableVersion: String?
    /// Whether a check has finished this launch, so Settings can say "Up to date".
    private(set) var hasChecked = false
    private(set) var lastError: String?
    private(set) var lastChecked: Date?

    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var canCheckObserver: AnyCancellable?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        canCheckObserver = controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] in self?.canCheck = $0 }
        lastChecked = controller.updater.lastUpdateCheckDate
    }

    /// Starts daily background checks, and checks now too: students with Launch at Login
    /// may run the app for days, but others only open it now and then.
    func start() {
        controller.startUpdater()
        controller.updater.checkForUpdatesInBackground()
    }

    /// Shows Sparkle's window: the waiting update, or a fresh check.
    func check() {
        controller.checkForUpdates(nil)
    }

    /// Menu bar apps aren't active, and macOS 14+ may ignore `activate()` from them,
    /// so Sparkle's windows would open behind others. Force them to the front.
    private func bringWindowsForward() {
        NSApp.activate()
        DispatchQueue.main.async {
            NSApp.windows.filter(\.isVisible).forEach { $0.orderFrontRegardless() }
        }
    }

    // MARK: SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        isChecking = true
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.displayVersionString
        lastError = nil
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        // Also how a background check reports a version the student skipped.
        availableVersion = nil
        lastError = nil
    }

    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice,
                 forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
        // Respect "Skip This Version". Critical updates don't offer it.
        if choice == .skip { availableVersion = nil }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let error = error as NSError
        let quiet: Set<Int> = [Int(SUError.noUpdateError.rawValue),
                               Int(SUError.installationCanceledError.rawValue)]
        guard error.domain == SUSparkleErrorDomain, !quiet.contains(error.code) else { return }
        lastError = error.localizedDescription
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
                 error: (any Error)?) {
        isChecking = false
        hasChecked = true
        lastChecked = updater.lastUpdateCheckDate
    }

    // MARK: SPUStandardUserDriverDelegate

    // A menu bar app has no Dock icon to badge, so let Sparkle use its gentle reminders
    // for background-found updates instead of warning about it.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if handleShowingUpdate { bringWindowsForward() }
    }

    func standardUserDriverWillShowModalAlert() {
        bringWindowsForward()
    }
}
