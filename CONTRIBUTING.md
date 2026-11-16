# Contributing to Folga

Thanks for helping! Issues and pull requests are welcome in English or Portuguese.

## Good first contributions

- **A new app or tool to measure and clean** (Cursor, Windsurf, Ollama, LM Studio, Xcode DerivedData,
  Gradle, CocoaPods, Homebrew…). Add an entry to [`Sources/Folga/Catalog.swift`](Sources/Folga/Catalog.swift):
  `group: .ai` for AI apps, `group: .dev` for developer tools, with `CacheRule`s for what is safe to delete.
- **Translations**: the UI is in Brazilian Portuguese today.
- **Bug reports**: include your macOS version and, if it's about sizes, the output of `Folga --report`.

## Ground rules

1. **Only regenerable data is deleted.** Caches, logs and old versions are fine. Settings, logins,
   memories, user files and Docker volumes are never touched. Chats go to the Trash, not deleted.
2. **Never test cleanup on your real data.** Point Folga at a fake home folder:
   `FOLGA_HOME=/tmp/fake-home .build/release/Folga --clean-test`.
3. **Cleaning needs explicit selection and double confirmation.** Don't add shortcuts that skip them.
4. **Builds must work with the Command Line Tools only** (no Xcode): don't use SwiftUI macros
   (`@State`, `@Observable`, `#Preview`). Use the `Flag` + `@StateObject` pattern in `Views.swift`.

## Workflow

```bash
swift build -c release
.build/release/Folga --report                # sizes per app/tool
.build/release/Folga --snapshot /tmp/folga   # PNGs of every screen, light and dark (attach to UI PRs)
FOLGA_HOME=/tmp/fake-home .build/release/Folga --clean-test
```

Open a pull request against `main` with what changed and how you tested it. Releases (signing,
appcast, DMG) are done by the maintainer with `scripts/release.sh`.
