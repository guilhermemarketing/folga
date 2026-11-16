import AppKit

@main
@MainActor
enum Launcher {
    static func main() {
        if Debug.handle(CommandLine.arguments) { return }
        let app = NSApplication.shared
        let controller = MenuController()
        app.delegate = controller
        app.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--panel-probe") { Debug.schedulePanelProbe(controller) }
        withExtendedLifetime(controller) { app.run() }
    }
}
