import AppKit

enum Cleaner {
    struct Result: Sendable {
        var deleted: Int64 = 0   // caches, gone for good
        var trashed: Int64 = 0   // old chats, recoverable from the Trash
        var failures = 0
        var total: Int64 { deleted + trashed }
    }

    /// Caches are regenerable, so they are deleted. Chats go to the Trash.
    static func clean(caches: [Entry], chats: [Entry], commands: [[String]] = []) -> Result {
        let fm = FileManager.default
        var r = Result()
        for e in caches where e.url == AppReport.dockerURL {
            if !Scanner.isSandboxedHome && Docker.prune() { r.deleted += e.size } else { r.failures += 1 }
        }
        for e in caches where isSafe(e.url) {
            do {
                try fm.removeItem(at: e.url)
                for extra in e.also where isSafe(extra) { try? fm.removeItem(at: extra) }
                r.deleted += e.size
            } catch { r.failures += 1 }
        }
        for e in chats where isSafe(e.url) {
            do { try fm.trashItem(at: e.url, resultingItemURL: nil); r.trashed += e.size } catch { r.failures += 1 }
        }
        pruneEmptyFolders(in: Scanner.resolve(".codex/sessions"))
        // Tool-native cleanup (pnpm store prune). Never in a fake home.
        if !Scanner.isSandboxedHome {
            for c in commands where !c.isEmpty { _ = Shell.run(c[0], Array(c.dropFirst()), timeout: 600) }
        }
        return r
    }

    /// Never touch anything outside the home folder, or the top level of it.
    static func isSafe(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let home = Scanner.home.standardizedFileURL.pathComponents
        let path = url.standardizedFileURL.pathComponents
        return path.count >= home.count + 2 && Array(path.prefix(home.count)) == home
    }

    private static func pruneEmptyFolders(in root: URL) {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        let dirs = e.compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.pathComponents.count > $1.pathComponents.count }
        for d in dirs where (try? fm.contentsOfDirectory(atPath: d.path))?.isEmpty == true {
            try? fm.removeItem(at: d)
        }
    }

    // MARK: - Quitting and reopening apps

    static func running(_ bundleIDs: [String]) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { bundleIDs.contains($0.bundleIdentifier ?? "") }
    }

    /// Asks the apps to quit and waits up to 15s. Returns true when all are gone.
    @MainActor
    static func quit(_ bundleIDs: [String]) async -> Bool {
        running(bundleIDs).forEach { $0.terminate() }
        for _ in 0..<60 {
            if running(bundleIDs).isEmpty { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return running(bundleIDs).isEmpty
    }

    static func reopen(_ url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
}
