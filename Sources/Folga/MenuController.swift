import AppKit
import Combine
import SwiftUI

/// The menu bar item and its window. Replaces SwiftUI's MenuBarExtra, which resized its window
/// around the bottom edge: collapsing "Desenvolvimento" left a gap under the menu bar.
/// Here the window's top is always pinned right under the status item.
@MainActor
final class MenuController: NSObject, NSApplicationDelegate {
    let store = Store()
    let awake = KeepAwake()
    let updater = Updater()

    private var item: NSStatusItem!
    private var panel: FolgaPanel!
    private var hosting: SizingHostingView<AnyView>!
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var bag = Set<AnyCancellable>()

    static let width: CGFloat = 340

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.imagePosition = .imageLeading

        let root = RootView().environmentObject(store).environmentObject(awake).environmentObject(updater)
        hosting = SizingHostingView(rootView: AnyView(root))
        hosting.onResize = { [weak self] in self?.fitToContent() }
        panel = FolgaPanel(content: hosting)

        Publishers.CombineLatest3(store.$disk, awake.$isOn, awake.$compactRemaining)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in self?.updateButton() }
            .store(in: &bag)
        updateButton()
    }

    // MARK: - Status item

    private func updateButton() {
        guard let button = item?.button else { return }
        let symbol = awake.isOn ? "cup.and.saucer.fill" : "internaldrive"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Folga")
        image?.isTemplate = true
        button.image = image
        let text = awake.isOn ? awake.compactRemaining : store.disk.map { bytesShort($0.available) } ?? ""
        button.title = text.isEmpty ? "" : " " + text
    }

    // MARK: - Window

    var isShown: Bool { panel?.isVisible == true }

    @objc func toggle() { isShown ? close() : show() }

    func show() {
        store.refreshIfStale()
        fitToContent()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        item.button?.highlight(true)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Esc closes from the main screen; elsewhere it means "back" (handled by the view).
            guard let self, event.keyCode == 53, case .overview = self.store.phase else { return event }
            self.close()
            return nil
        }
    }

    func close() {
        panel.orderOut(nil)
        item.button?.highlight(false)
        [clickMonitor, keyMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        clickMonitor = nil
        keyMonitor = nil
        if case .done = store.phase { store.phase = .overview }
    }

    /// Size to the SwiftUI content, top edge glued under the status item.
    func fitToContent() {
        guard let panel, let buttonWindow = item.button?.window, let screen = buttonWindow.screen ?? NSScreen.main else { return }
        let height = ceil(hosting.fittingSize.height)
        let anchor = buttonWindow.frame
        let top = anchor.minY - 4
        var x = anchor.midX - Self.width / 2
        x = min(max(x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - Self.width - 8)
        let frame = NSRect(x: x, y: top - height, width: Self.width, height: height)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
        }
    }

    /// Distance between the menu bar and the window's top, for the --panel-probe check.
    var gapUnderMenuBar: CGFloat? {
        guard let anchor = item.button?.window?.frame, isShown else { return nil }
        return anchor.minY - panel.frame.maxY
    }
}

/// Borderless, rounded, translucent window like the system's menu bar windows.
final class FolgaPanel: NSPanel {
    init(content: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: MenuController.width, height: 400),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        isMovable = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let glass = NSVisualEffectView()
        glass.material = .popover
        glass.state = .active
        glass.blendingMode = .behindWindow
        glass.maskImage = Self.roundedMask(radius: 12)
        content.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            content.topAnchor.constraint(equalTo: glass.topAnchor),
            content.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])
        contentView = glass
    }

    override var canBecomeKey: Bool { true }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Tells the controller whenever the SwiftUI content wants a different size.
final class SizingHostingView<Content: View>: NSHostingView<Content> {
    var onResize: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.onResize?() }
    }
}
