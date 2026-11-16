import SwiftUI
import ServiceManagement

/// Developer entry points: `--report` prints what the app sees,
/// `--snapshot <dir>` renders every screen to PNG.
@MainActor
enum Debug {
    static func handle(_ args: [String]) -> Bool {
        if args.contains("--report") { report(); return true }
        if args.contains("--clean-test") { cleanTest(); return true }
        if args.contains("--awake-test") {
            let awake = KeepAwake()
            awake.addHalfHour()
            print("on \(awake.isOn) até \(awake.endsAt!) barra: \(awake.compactRemaining)")
            print([0, 45, 60, 61, 1799, 1800, 3540, 3600, 3601, 5400, 86400].map(KeepAwake.compact))
            RunLoop.main.run(until: .now.addingTimeInterval(6))
            awake.setOn(false)
            print("off \(awake.isOn)")
            return true
        }
        if args.contains("--login-status") { print(SMAppService.mainApp.status.rawValue); return true }
        if args.contains("--enable-login") {
            do { try SMAppService.mainApp.register(); print("ok \(SMAppService.mainApp.status.rawValue)") }
            catch { print("erro: \(error)") }
            return true
        }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            snapshot(to: URL(fileURLWithPath: args[i + 1])); return true
        }
        return false
    }

    private static func wait<T>(_ work: @escaping () async -> T) -> T {
        var out: T?
        Task { out = await work() }
        while out == nil { RunLoop.main.run(until: .now.addingTimeInterval(0.05)) }
        return out!
    }

    static func report() {
        let reports = wait { await Scanner.scan() }
        for r in reports {
            print("\(r.name): total \(bytes(r.total)) · app \(bytes(r.appSize)) · cache \(bytes(r.cacheSize)) (\(r.caches.count) itens) · conversas \(bytes(r.chatSize)) (\(r.chats.count)) · paradas 30d \(bytes(r.oldChats(days: 30).reduce(0) { $0 + $1.size })) (\(r.oldChats(days: 30).count))")
        }
    }

    /// Cleans everything the catalog allows, but only inside a fake FOLGA_HOME.
    static func cleanTest() {
        guard Scanner.isSandboxedHome else { print("FOLGA_HOME obrigatório"); return }
        let reports = wait { await Scanner.scan() }
        let r = Cleaner.clean(caches: reports.flatMap(\.caches), chats: reports.flatMap { $0.oldChats(days: 30) })
        print("deleted \(r.deleted) trashed \(r.trashed) failures \(r.failures)")
    }

    @MainActor
    static func snapshot(to dir: URL) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = Store()
        let awake = KeepAwake()
        let updater = Updater()
        wait { await store.refresh() }
        while store.scanning || store.reports.isEmpty { RunLoop.main.run(until: .now.addingTimeInterval(0.1)) }
        let phases: [(String, Store.Phase)] = [
            ("overview", .overview), ("review", .review), ("confirm", .confirm), ("cleaning", .cleaning),
            ("done", .done(Cleaner.Result(deleted: 2_400_000_000, trashed: 512_000_000, failures: 0))),
        ]
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            appearance == .aqua ? awake.setOn(false) : awake.addHalfHour()
            // light: nothing picked; dark: ChatGPT + Antigravity picked
            store.devExpanded = appearance == .darkAqua
            let darkPicks: Set<String> = ["chatgpt", "antigravity", "uv", "browsers"]
            for r in store.reports where store.isSelected(r) != (appearance == .darkAqua && darkPicks.contains(r.id)) {
                store.toggle(r)
            }
            for (name, phase) in phases {
                store.phase = phase
                let view = NSHostingView(rootView: RootView().environmentObject(store).environmentObject(awake).environmentObject(updater)
                    .background(Color(nsColor: .windowBackgroundColor)))
                view.appearance = NSAppearance(named: appearance)
                view.frame.size = view.fittingSize
                let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.contentView = view
                RunLoop.main.run(until: .now.addingTimeInterval(0.6))
                view.layoutSubtreeIfNeeded()
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let suffix = appearance == .aqua ? "light" : "dark"
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: dir.appendingPathComponent("\(name)-\(suffix).png"))
            }
        }
        print("ok")
    }
}
