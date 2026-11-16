import Foundation

/// Runs developer CLIs (docker, pnpm) from a GUI app, which starts with a bare PATH.
enum Shell {
    static let searchPath: [String] = {
        let home = Scanner.home.path
        return ["\(home)/.npm-global/bin", "\(home)/Library/pnpm", "\(home)/.local/share/pnpm",
                "\(home)/.local/bin", "\(home)/.bun/bin", "\(home)/.volta/bin",
                "\(home)/.docker/bin", "\(home)/.orbstack/bin",
                "/Applications/Docker.app/Contents/Resources/bin",
                "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
    }()

    static func find(_ tool: String) -> URL? {
        searchPath.map { URL(fileURLWithPath: $0).appendingPathComponent(tool) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Output and exit status, or nil when the tool is missing or doesn't finish in time.
    static func run(_ tool: String, _ args: [String], timeout: TimeInterval = 15) -> (status: Int32, output: String)? {
        guard let exe = find(tool) else { return nil }
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath.joined(separator: ":")
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { return nil }
        // Drain while waiting so a chatty command can't fill the pipe and stall.
        var data = Data()
        let reader = DispatchQueue(label: "folga.shell")
        reader.async { data = pipe.fileHandleForReading.readDataToEndOfFile() }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            return nil
        }
        reader.sync {}
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

enum Docker {
    /// Space Docker can give back without touching volumes, or nil when it isn't running.
    static func usage() -> (total: Int64, reclaimable: Int64)? {
        guard let r = Shell.run("docker", ["system", "df", "--format", "{{json .}}"]), r.status == 0 else { return nil }
        var total: Int64 = 0, free: Int64 = 0
        for line in r.output.split(separator: "\n") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            let type = obj["Type"] as? String ?? ""
            total += parse(obj["Size"] as? String ?? "")
            if !type.localizedCaseInsensitiveContains("volume") {
                free += parse(obj["Reclaimable"] as? String ?? "")
            }
        }
        return (total, free)
    }

    static func prune() -> Bool {
        let system = Shell.run("docker", ["system", "prune", "--all", "--force"], timeout: 600)
        _ = Shell.run("docker", ["builder", "prune", "--all", "--force"], timeout: 600)
        return system?.status == 0
    }

    /// "1.23GB", "800MB (66%)", "0B" → bytes (Docker uses powers of 1000).
    static func parse(_ text: String) -> Int64 {
        let s = text.split(separator: " ").first.map(String.init) ?? ""
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("KB", 1e3), ("B", 1)]
        for (u, mult) in units where s.hasSuffix(u) {
            return Int64((Double(s.dropLast(u.count)) ?? 0) * mult)
        }
        return 0
    }
}
