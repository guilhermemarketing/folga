import Foundation

/// Where each AI app or dev tool keeps its things on disk. Paths are relative to the home
/// folder unless they start with "/".
struct AIApp: Identifiable, Sendable {
    enum Group: Sendable { case ai, dev }

    let id: String
    let name: String
    let bundleIDs: [String]
    let bundles: [String]          // the .app itself
    let data: [String]             // everything else the app writes (must not nest); empty = caches only
    let caches: [CacheRule]        // regenerable; deleted outright, app must be closed
    let chats: [ChatRule]          // old sessions; moved to the Trash
    var group: Group = .ai
    var symbol: String? = nil      // icon when there is no .app
    var afterClean: [String]? = nil // command run after its caches are cleaned
}

enum CacheRule: Sendable {
    /// Everything inside the folder (the folder itself stays).
    case contents(String)
    /// Items inside the folder untouched for `days`.
    case contentsOlderThan(String, days: Int)
    /// Items inside the folder whose name contains `include` and not `exclude`.
    case matching(String, include: String, exclude: String? = nil)
    /// Hugging Face hub models (models--org--name), whose files may be symlinks into a shared
    /// hub/blobs folder. Each model takes the blobs only it references.
    case hubModels(String, include: String, exclude: String? = nil)
    /// Every version folder except the newest one.
    case olderVersions(String)
    /// Keeps the newest of each family ("chromium-1254" beats "chromium-1243").
    /// Depth 2 looks one folder deeper (~/.cache/puppeteer/chrome/mac_arm-131…).
    case olderVersionsByFamily(String, depth: Int = 1)
    /// Unused images, stopped containers and build cache. Volumes are never touched.
    case dockerPrune
}

struct ChatRule: Sendable {
    enum Depth: Sendable { case children, grandchildren, files }
    let folder: String
    let depth: Depth
    var skip: Set<String> = []
}

private let chromium = ["Cache", "Code Cache", "GPUCache", "DawnWebGPUCache",
                        "DawnGraphiteCache", "GraphiteDawnCache", "CachedData", "Crashpad", "logs"]

private func chromiumCaches(_ root: String) -> [CacheRule] {
    chromium.map { .contents("\(root)/\($0)") }
}

enum Catalog {
    static let apps: [AIApp] = [
        AIApp(
            id: "chatgpt",
            name: "ChatGPT",
            bundleIDs: ["com.openai.codex", "com.openai.chat"],
            bundles: ["/Applications/ChatGPT.app", "Applications/ChatGPT.app",
                      "/Applications/Codex.app", "Applications/Codex.app"],
            data: [".codex",
                   "Library/Application Support/Codex",
                   "Library/Application Support/com.openai.codex",
                   "Library/Application Support/com.openai.chat",
                   "Library/Application Support/ChatGPT Meetings",
                   "Library/Application Support/OpenAI",
                   "Library/Caches/Codex",
                   "Library/Caches/com.openai.codex",
                   "Library/Caches/com.openai.chat",
                   "Library/Caches/com.openai.chatgpt-meetings",
                   "Library/Caches/com.openai.sky.CUAService",
                   "Library/Caches/com.openai.sky.CUAService.cli",
                   "Library/Logs/com.openai.codex"],
            caches: [.contents("Library/Caches/Codex"),
                     .contents("Library/Caches/com.openai.codex"),
                     .contents("Library/Caches/com.openai.chat"),
                     .contents("Library/Caches/com.openai.chatgpt-meetings"),
                     .contents("Library/Caches/com.openai.sky.CUAService"),
                     .contents("Library/Caches/com.openai.sky.CUAService.cli"),
                     .contents("Library/Logs/com.openai.codex"),
                     .contents("Library/Application Support/ChatGPT Meetings/Logs"),
                     .contents(".codex/cache")]
                + chromiumCaches("Library/Application Support/Codex")
                + chromiumCaches("Library/Application Support/Codex/Default"),
            chats: [ChatRule(folder: ".codex/sessions", depth: .files),
                    ChatRule(folder: ".codex/archived_sessions", depth: .children),
                    ChatRule(folder: ".codex/shell_snapshots", depth: .children)]
        ),
        AIApp(
            id: "claude",
            name: "Claude",
            bundleIDs: ["com.anthropic.claudefordesktop"],
            bundles: ["/Applications/Claude.app", "Applications/Claude.app"],
            data: ["Library/Application Support/Claude",
                   ".claude", ".claude.json",
                   ".local/share/claude", ".local/state/claude", ".cache/claude",
                   "Library/Caches/com.anthropic.claudefordesktop",
                   "Library/Caches/com.anthropic.claudefordesktop.ShipIt",
                   "Library/Caches/claude-cli-nodejs",
                   "Library/Logs/Claude"],
            caches: [.contents("Library/Caches/com.anthropic.claudefordesktop"),
                     .contents("Library/Caches/com.anthropic.claudefordesktop.ShipIt"),
                     .contents("Library/Caches/claude-cli-nodejs"),
                     .contents("Library/Logs/Claude"),
                     .olderVersions("Library/Application Support/Claude/claude-code")]
                + chromiumCaches("Library/Application Support/Claude"),
            chats: [ChatRule(folder: ".claude/projects", depth: .grandchildren, skip: ["memory"]),
                    ChatRule(folder: ".claude/file-history", depth: .children),
                    ChatRule(folder: ".claude/todos", depth: .children),
                    ChatRule(folder: ".claude/debug", depth: .children),
                    ChatRule(folder: ".claude/shell-snapshots", depth: .children)]
        ),
        AIApp(
            id: "antigravity",
            name: "Antigravity",
            bundleIDs: ["com.google.antigravity", "com.google.antigravity-ide"],
            bundles: ["/Applications/Antigravity.app", "/Applications/Antigravity IDE.app",
                      "Applications/Antigravity.app", "Applications/Antigravity IDE.app"],
            data: ["Library/Application Support/Antigravity",
                   "Library/Application Support/Antigravity IDE",
                   ".gemini/antigravity", ".gemini/antigravity-ide",
                   ".antigravity", ".antigravity-ide",
                   "Library/Caches/antigravity",
                   "Library/Caches/com.google.antigravity",
                   "Library/Caches/com.google.antigravity.ShipIt",
                   "Library/Caches/com.google.antigravity-ide",
                   "Library/Caches/com.google.antigravity-ide.ShipIt",
                   "Library/Logs/Antigravity"],
            caches: [.contents("Library/Caches/antigravity"),
                     .contents("Library/Caches/com.google.antigravity"),
                     .contents("Library/Caches/com.google.antigravity.ShipIt"),
                     .contents("Library/Caches/com.google.antigravity-ide"),
                     .contents("Library/Caches/com.google.antigravity-ide.ShipIt"),
                     .contents("Library/Logs/Antigravity"),
                     .contents(".gemini/antigravity/cache"),
                     .contents("Library/Application Support/Antigravity IDE/CachedExtensionVSIXs")]
                + chromiumCaches("Library/Application Support/Antigravity")
                + chromiumCaches("Library/Application Support/Antigravity IDE"),
            chats: [ChatRule(folder: ".gemini/antigravity/brain", depth: .children),
                    ChatRule(folder: ".gemini/antigravity/conversations", depth: .children),
                    ChatRule(folder: ".gemini/antigravity-ide/brain", depth: .children),
                    ChatRule(folder: ".gemini/antigravity-ide/conversations", depth: .children)]
        ),
    ] + devTools

    static let devTools: [AIApp] = [
        AIApp(id: "pnpm", name: "pnpm", bundleIDs: [], bundles: [],
              data: ["Library/pnpm/store", "Library/Caches/pnpm", ".local/share/pnpm/store", ".pnpm-store"],
              caches: [.contents("Library/Caches/pnpm"),
                       .olderVersions("Library/pnpm/store"),
                       .olderVersions(".local/share/pnpm/store"),
                       .olderVersions(".pnpm-store")],
              chats: [], group: .dev, symbol: "shippingbox", afterClean: ["pnpm", "store", "prune"]),
        AIApp(id: "npm", name: "npm", bundleIDs: [], bundles: [],
              data: [".npm/_cacache", ".npm/_logs", ".npm/_npx"],
              caches: [.contents(".npm/_cacache"),
                       .contents(".npm/_logs"),
                       .contentsOlderThan(".npm/_npx", days: 7)],   // MCP servers run from here
              chats: [], group: .dev, symbol: "shippingbox.fill"),
        AIApp(id: "node", name: "Node", bundleIDs: [], bundles: [],
              data: ["Library/Caches/node-gyp", ".node-gyp", ".cache/node", ".nvm/.cache"],
              caches: [.contents("Library/Caches/node-gyp"), .contents(".node-gyp"),
                       .contents(".cache/node"), .contents(".nvm/.cache")],
              chats: [], group: .dev, symbol: "hexagon"),
        AIApp(id: "uv", name: "Python (uv)", bundleIDs: [], bundles: [],
              data: [".cache/uv", "Library/Caches/pip"],
              caches: [.contents(".cache/uv"), .contents("Library/Caches/pip")],
              chats: [], group: .dev, symbol: "bolt"),
        AIApp(id: "bun", name: "Bun", bundleIDs: [], bundles: [],
              data: [".bun/install/cache", "Library/Caches/bun"],
              caches: [.contents(".bun/install/cache"), .contents("Library/Caches/bun")],
              chats: [], group: .dev, symbol: "circle.grid.2x2"),
        AIApp(id: "docker", name: "Docker", bundleIDs: [], bundles: ["/Applications/Docker.app"],
              data: [], caches: [.dockerPrune],
              chats: [], group: .dev, symbol: "cube.box"),
        AIApp(id: "huggingface", name: "Modelos Hugging Face", bundleIDs: [], bundles: [],
              data: [],   // whisper models live here too; they are counted under Whisper
              caches: [.hubModels(".cache/huggingface/hub", include: "models--", exclude: "whisper"),
                       .hubModels(".cache/huggingface/hub", include: "datasets--"),
                       .contents(".cache/huggingface/xet")],
              chats: [], group: .dev, symbol: "face.smiling"),
        AIApp(id: "browsers", name: "Playwright + Puppeteer", bundleIDs: [], bundles: [],
              data: ["Library/Caches/ms-playwright", ".cache/ms-playwright", ".cache/puppeteer"],
              caches: [.olderVersionsByFamily("Library/Caches/ms-playwright"),
                       .olderVersionsByFamily(".cache/ms-playwright"),
                       .olderVersionsByFamily(".cache/puppeteer", depth: 2)],
              chats: [], group: .dev, symbol: "globe"),
        AIApp(id: "whisper", name: "Whisper", bundleIDs: [], bundles: [],
              data: [],
              caches: [.hubModels(".cache/huggingface/hub", include: "whisper"),
                       .contents(".cache/whisper")],
              chats: [], group: .dev, symbol: "waveform"),
    ]
}
