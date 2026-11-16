import Foundation

struct Entry: Sendable, Hashable {
    let url: URL
    let size: Int64
    let lastUsed: Date
    var also: [URL] = []   // removed together with `url` (shared blobs a model owns)
}

struct AppReport: Sendable, Identifiable {
    let id: String
    let name: String
    var group: AIApp.Group = .ai
    var symbol: String? = nil
    var afterClean: [String]? = nil
    var note: String? = nil         // shown instead of sizes ("Abra o Docker para medir")
    let bundleIDs: [String]
    let appURL: URL?
    let appSize: Int64
    let dataSize: Int64
    let caches: [Entry]
    let chats: [Entry]

    var total: Int64 { appSize + dataSize }
    static let dockerURL = URL(string: "docker:prune")!
    var cacheSize: Int64 { caches.reduce(0) { $0 + $1.size } }
    var chatSize: Int64 { chats.reduce(0) { $0 + $1.size } }
    func oldChats(days: Int, now: Date = .now) -> [Entry] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return chats.filter { $0.lastUsed < cutoff }
    }
}

struct DiskInfo: Sendable {
    let name: String
    let total: Int64
    let available: Int64
    var used: Int64 { total - available }

    static func current() -> DiskInfo? {
        let root = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey,
                                         .volumeLocalizedNameKey]
        guard let v = try? root.resourceValues(forKeys: keys),
              let total = v.volumeTotalCapacity,
              let free = v.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskInfo(name: v.volumeLocalizedName ?? "Macintosh HD", total: Int64(total), available: free)
    }
}

enum Scanner {
    /// FOLGA_HOME lets tests point the whole app at a fake home folder.
    static let home: URL = {
        if let fake = ProcessInfo.processInfo.environment["FOLGA_HOME"] {
            return URL(fileURLWithPath: fake, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()
    static let isSandboxedHome = ProcessInfo.processInfo.environment["FOLGA_HOME"] != nil

    static func resolve(_ path: String) -> URL {
        if path.hasPrefix("/") {
            return isSandboxedHome ? home.appendingPathComponent(String(path.dropFirst()))
                                   : URL(fileURLWithPath: path)
        }
        return home.appendingPathComponent(path)
    }

    static func scan(_ apps: [AIApp] = Catalog.apps) async -> [AppReport] {
        await withTaskGroup(of: (Int, AppReport).self) { group in
            for (i, app) in apps.enumerated() {
                group.addTask { (i, report(for: app)) }
            }
            var out = [(Int, AppReport)]()
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    static func report(for app: AIApp) -> AppReport {
        let fm = FileManager.default
        let bundles = app.bundles.map(resolve).filter { fm.fileExists(atPath: $0.path) }
        let appSize = bundles.reduce(Int64(0)) { $0 + measure($1).size }
        var dataSize = app.data.map(resolve).reduce(Int64(0)) { $0 + measure($1).size }
        var note: String?

        var caches: [Entry] = []
        for rule in app.caches {
            switch rule {
            case .contents(let p):
                caches += children(of: resolve(p)).map(entry)
            case .contentsOlderThan(let p, let days):
                let cutoff = Date.now.addingTimeInterval(-Double(days) * 86_400)
                caches += children(of: resolve(p)).map(entry).filter { $0.lastUsed < cutoff }
            case .matching(let p, let include, let exclude):
                caches += children(of: resolve(p)).filter {
                    let name = $0.lastPathComponent.lowercased()
                    return name.contains(include.lowercased()) && !(exclude.map { name.contains($0.lowercased()) } ?? false)
                }.map(entry)
            case .hubModels(let p, let include, let exclude):
                caches += hubModels(in: resolve(p), include: include, exclude: exclude)
            case .olderVersions(let p):
                caches += newestDropped(children(of: resolve(p))).map(entry)
            case .olderVersionsByFamily(let p, let depth):
                let roots = depth == 1 ? [resolve(p)] : children(of: resolve(p))
                for root in roots {
                    let families = Dictionary(grouping: children(of: root)) { family($0.lastPathComponent) }
                    for (_, versions) in families { caches += newestDropped(versions).map(entry) }
                }
            case .dockerPrune:
                guard isSandboxedHome == false, Shell.find("docker") != nil else { break }
                if let usage = Docker.usage() {
                    dataSize += usage.total
                    if usage.reclaimable > 0 {
                        caches.append(Entry(url: AppReport.dockerURL, size: usage.reclaimable, lastUsed: .distantPast))
                    }
                } else {
                    note = "Abra o Docker para medir"
                }
            }
        }
        if app.data.isEmpty && !app.caches.contains(where: { if case .dockerPrune = $0 { true } else { false } }) {
            dataSize = caches.reduce(0) { $0 + $1.size }
        }

        var chats: [Entry] = []
        for rule in app.chats {
            let root = resolve(rule.folder)
            switch rule.depth {
            case .children:
                chats += children(of: root).filter { !rule.skip.contains($0.lastPathComponent) }.map(entry)
            case .grandchildren:
                for dir in children(of: root) {
                    chats += children(of: dir).filter { !rule.skip.contains($0.lastPathComponent) }.map(entry)
                }
            case .files:
                chats += files(under: root).map(entry)
            }
        }

        return AppReport(id: app.id, name: app.name, group: app.group, symbol: app.symbol,
                         afterClean: app.afterClean, note: note, bundleIDs: app.bundleIDs,
                         appURL: bundles.first, appSize: appSize, dataSize: dataSize,
                         caches: caches.filter { $0.size > 0 }, chats: chats)
    }

    // MARK: - File system

    private static func entry(_ url: URL) -> Entry {
        let m = measure(url)
        return Entry(url: url, size: m.size, lastUsed: m.lastUsed)
    }

    /// One entry per model folder. Blobs reached through symlinks count (and get deleted) only
    /// when no other model points at them.
    private static func hubModels(in hub: URL, include: String, exclude: String?) -> [Entry] {
        let fm = FileManager.default
        let all = children(of: hub).filter {
            let n = $0.lastPathComponent
            return n.hasPrefix("models--") || n.hasPrefix("datasets--") || n.hasPrefix("spaces--")
        }
        var targets: [URL: Set<URL>] = [:]          // model → blobs outside it
        var owners: [URL: Int] = [:]               // blob → how many models use it
        for model in all {
            var mine = Set<URL>()
            let e = fm.enumerator(at: model, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [])
            while let item = e?.nextObject() as? URL {
                guard (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true else { continue }
                let target = item.resolvingSymlinksInPath().standardizedFileURL
                if !target.path.hasPrefix(model.standardizedFileURL.path + "/"), target.path.hasPrefix(hub.standardizedFileURL.path + "/") {
                    mine.insert(target)
                }
            }
            targets[model] = mine
            for t in mine { owners[t, default: 0] += 1 }
        }
        return all.filter {
            let n = $0.lastPathComponent.lowercased()
            return n.contains(include.lowercased()) && !(exclude.map { n.contains($0.lowercased()) } ?? false)
        }.map { model in
            let own = measure(model)
            let exclusive = (targets[model] ?? []).filter { owners[$0] == 1 }
            let shared = exclusive.reduce(Int64(0)) { $0 + measure($1).size }
            return Entry(url: model, size: own.size + shared, lastUsed: own.lastUsed, also: Array(exclusive))
        }
    }

    private static func newestDropped(_ urls: [URL]) -> ArraySlice<URL> {
        urls.sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending }
            .dropLast()
    }

    /// "chromium_headless_shell-1254" → "chromium_headless_shell"; "mac_arm-131.0.1" → "mac_arm".
    private static func family(_ name: String) -> String {
        guard let dash = name.lastIndex(of: "-") else { return name }
        return String(name[..<dash])
    }

    private static func children(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
    }

    private static func files(under url: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return e.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }

    private static let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
                                                 .totalFileAllocatedSizeKey, .contentModificationDateKey]

    /// Allocated size on disk and most recent modification anywhere inside.
    static func measure(_ url: URL) -> (size: Int64, lastUsed: Date) {
        let set = Set(keys)
        guard let v = try? url.resourceValues(forKeys: set) else { return (0, .distantPast) }
        var last = v.contentModificationDate ?? .distantPast
        if v.isSymbolicLink == true { return (0, last) }
        if v.isDirectory != true { return (Int64(v.totalFileAllocatedSize ?? 0), last) }

        var size: Int64 = 0
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        while let item = e?.nextObject() as? URL {
            guard let r = try? item.resourceValues(forKeys: set) else { continue }
            if let d = r.contentModificationDate, d > last { last = d }
            if r.isRegularFile == true { size += Int64(r.totalFileAllocatedSize ?? 0) }
        }
        return (size, last)
    }
}
