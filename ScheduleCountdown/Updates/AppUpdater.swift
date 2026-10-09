import AppKit
import Combine
import Sparkle

/// App self-updates through Sparkle. The feed and EdDSA public key come from Info.plist
/// (`SUFeedURL`, `SUPublicEDKey`); background checks are on via `SUEnableAutomaticChecks`.
@Observable
final class AppUpdater: NSObject, SPUStandardUserDriverDelegate {
    private(set) var canCheck = false

    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var canCheckObserver: AnyCancellable?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        canCheckObserver = controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] in self?.canCheck = $0 }
    }

    func start() {
        controller.startUpdater()
    }

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
