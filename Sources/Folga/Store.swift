import AppKit
import ServiceManagement

@MainActor
final class Store: ObservableObject {
    enum Phase { case overview, review, confirm, cleaning, done(Cleaner.Result) }

    @Published private(set) var disk = DiskInfo.current()
    @Published private(set) var reports: [AppReport] = []
    @Published private(set) var scanning = false
    @Published private(set) var lastScan: Date?
    @Published private(set) var runningIDs: Set<String> = []
    @Published var phase: Phase = .overview

    @Published var includeCache = true
    @Published var includeChats = true
    @Published var quitRunning = false
    /// AIs picked for cleaning. Starts empty: nothing is cleaned until you choose.
    @Published private(set) var selected: Set<String> {
        didSet { UserDefaults.standard.set(Array(selected), forKey: "selectedApps") }
    }
    @Published var chatDays: Int {
        didSet { UserDefaults.standard.set(chatDays, forKey: "chatDays") }
    }

    private var timer: Timer?

    init() {
        let saved = UserDefaults.standard.integer(forKey: "chatDays")
        chatDays = saved == 0 ? 30 : saved
        selected = Set(UserDefaults.standard.stringArray(forKey: "selectedApps") ?? [])
        updateRunning()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateRunning() }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.disk = DiskInfo.current() }
        }
        Task { await refresh() }
    }

    // MARK: - Derived numbers

    var aiReports: [AppReport] { reports.filter { $0.group == .ai } }
    /// Dev tools that exist on this Mac.
    var devReports: [AppReport] { reports.filter { $0.group == .dev && ($0.total > 0 || $0.note != nil) } }
    var aiTotal: Int64 { aiReports.reduce(0) { $0 + $1.total } }
    var devTotal: Int64 { devReports.reduce(0) { $0 + $1.total } }

    @Published var devExpanded = UserDefaults.standard.bool(forKey: "devExpanded") {
        didSet { UserDefaults.standard.set(devExpanded, forKey: "devExpanded") }
    }

    func isRunning(_ r: AppReport) -> Bool { runningIDs.contains(r.id) }

    func isSelected(_ r: AppReport) -> Bool { selected.contains(r.id) }

    func toggle(_ r: AppReport) {
        if selected.contains(r.id) { selected.remove(r.id) } else { selected.insert(r.id) }
    }

    var selectedReports: [AppReport] { reports.filter(isSelected) }

    /// Caches of an open app only count when we're allowed to close it.
    func caches(for r: AppReport, ignoringSelection: Bool = false) -> [Entry] {
        guard includeCache, ignoringSelection || isSelected(r), !isRunning(r) || quitRunning else { return [] }
        return r.caches
    }

    func chats(for r: AppReport, ignoringSelection: Bool = false) -> [Entry] {
        guard includeChats, ignoringSelection || isSelected(r) else { return [] }
        return r.oldChats(days: chatDays)
    }

    func reclaimable(_ r: AppReport, ignoringSelection: Bool = false) -> Int64 {
        (caches(for: r, ignoringSelection: ignoringSelection) + chats(for: r, ignoringSelection: ignoringSelection))
            .reduce(0) { $0 + $1.size }
    }

    var reclaimable: Int64 { reports.reduce(0) { $0 + reclaimable($1) } }
    var cacheToClean: Int64 { reports.reduce(0) { $0 + caches(for: $1).reduce(0) { $0 + $1.size } } }
    var chatsToClean: Int64 { reports.reduce(0) { $0 + chats(for: $1).reduce(0) { $0 + $1.size } } }
    var cacheTotal: Int64 { selectedReports.reduce(0) { $0 + $1.cacheSize } }
    var oldChatTotal: Int64 { selectedReports.reduce(0) { $0 + $1.oldChats(days: chatDays).reduce(0) { $0 + $1.size } } }

    /// Open, selected apps that are holding cache we could free by closing them.
    var blockingApps: [AppReport] { selectedReports.filter { isRunning($0) && $0.cacheSize > 0 } }
    var blockedCache: Int64 { blockingApps.reduce(0) { $0 + $1.cacheSize } }

    // MARK: - Actions

    func refresh() async {
        guard !scanning else { return }
        scanning = true
        disk = DiskInfo.current()
        reports = await Task.detached(priority: .userInitiated) { await Scanner.scan() }.value
        lastScan = .now
        scanning = false
    }

    /// Re-scan when the window opens, unless the numbers are fresh.
    func refreshIfStale() {
        disk = DiskInfo.current()
        if let last = lastScan, Date.now.timeIntervalSince(last) < 30 { return }
        Task { await refresh() }
    }

    func clean() async {
        phase = .cleaning
        var reopen: [URL] = []

        if includeCache && quitRunning {
            for r in blockingApps {
                if await Cleaner.quit(r.bundleIDs), let url = r.appURL { reopen.append(url) }
            }
            updateRunning()
        }

        let cacheItems = reports.flatMap { caches(for: $0) }
        let chatItems = reports.flatMap { chats(for: $0) }
        let commands = reports.filter { !caches(for: $0).isEmpty }.compactMap(\.afterClean)
        let result = await Task.detached(priority: .userInitiated) {
            Cleaner.clean(caches: cacheItems, chats: chatItems, commands: commands)
        }.value

        reopen.forEach(Cleaner.reopen)
        lastScan = nil
        await refresh()
        phase = .done(result)
    }

    private func updateRunning() {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        runningIDs = Set(Catalog.apps.filter { !ids.isDisjoint(with: $0.bundleIDs) }.map(\.id))
    }

    // MARK: - Login item

    var opensAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }
}
