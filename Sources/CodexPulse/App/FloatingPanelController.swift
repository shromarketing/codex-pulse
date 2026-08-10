import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController {
    static let shared = FloatingPanelController()

    private var panel: NSPanel?

    private init() {}

    func show() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let root = FloatingWidgetView()
            .environmentObject(AppState.shared)
            .environmentObject(SettingsStore.shared)
        let hosting = NSHostingView(rootView: root)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 270, height: 330),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Codex Pulse"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hosting
        panel.setFrameAutosaveName("CodexPulseFloatingWidget")
        if !panel.setFrameUsingName("CodexPulseFloatingWidget") {
            panel.center()
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        guard let panel else {
            show()
            return
        }
        panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless()
    }
}
