import Sparkle
import SwiftUI

/// Sparkle updates, checked daily against appcast.xml on GitHub.
@MainActor
final class Updater: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    @Published private(set) var canCheck = false
    private var controller: SPUStandardUpdaterController?

    /// Only a bundled build has the feed URL and key; the bare `swift build` binary skips Sparkle.
    static var isAvailable: Bool { Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil }

    static var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return v ?? "dev"
    }

    override init() {
        super.init()
        guard Self.isAvailable else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        self.controller = controller
    }

    func check() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    // A menu bar app has no Dock icon to badge, so let Sparkle show scheduled updates itself.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}
