import AppKit
import SwiftUI

/// Keeps the menu bar window glued under the menu bar. AppKit resizes windows around their
/// bottom edge, so when the content gets shorter (collapsing "Desenvolvimento", going back from
/// a taller screen) the top would drop and leave a gap under the menu bar.
struct TopAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { AnchorView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class AnchorView: NSView {
        private var observers: [NSObjectProtocol] = []
        private var gap: CGFloat?   // distance from the menu bar, as the system first placed us

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.anchor(learning: true) }
            })
            observers.append(center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.anchor(learning: false) }
            })
        }

        private func anchor(learning: Bool) {
            guard let window, let screen = window.screen else { return }
            let menuBarBottom = screen.visibleFrame.maxY
            if learning && gap == nil {
                let observed = menuBarBottom - window.frame.maxY
                gap = (0...24).contains(observed) ? observed : 0
            }
            let top = menuBarBottom - (gap ?? 0)
            if abs(window.frame.maxY - top) > 0.5 {
                window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
            }
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
