import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    static let shared = FloatingPanelController()

    private var panel: NSPanel?
    private var isRecordingAdaptiveSize = false

    private override init() {
        super.init()
    }

    func show() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let root = FloatingWidgetView()
            .environmentObject(AppState.shared)
            .environmentObject(SettingsStore.shared)
            .environment(\.locale, SettingsStore.shared.language.locale)
        let hosting = NSHostingView(rootView: root)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: preferredWidgetSize(for: SettingsStore.shared.widgetPresentation)),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Codex Pulse"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 126, height: 52)
        panel.maxSize = NSSize(width: 560, height: 620)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.delegate = self
        panel.contentView = hosting
        hideSystemWindowControls(on: panel)
        panel.setFrameAutosaveName("CodexPulseFloatingWidget")
        let restoredFrame = panel.setFrameUsingName("CodexPulseFloatingWidget")
        if !restoredFrame {
            panel.center()
        }
        panel.orderFrontRegardless()
        self.panel = panel
        applySettings(SettingsStore.shared)
        if SettingsStore.shared.widgetPresentation == .adaptive,
           restoredFrame,
           restoredAdaptiveNeedsCompactPreset(panel.contentLayoutRect.size) {
            isRecordingAdaptiveSize = true
            SettingsStore.shared.widgetPresentation = .compact
            isRecordingAdaptiveSize = false
            resize(to: .compact, animated: false)
        } else if SettingsStore.shared.widgetPresentation != .adaptive
                    || !restoredFrame {
            resize(to: SettingsStore.shared.widgetPresentation, animated: false)
        }
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

    func showAndFocus() {
        show()
        panel?.orderFrontRegardless()
    }

    func toggleExpanded(isCurrentlyExpanded: Bool) {
        let settings = SettingsStore.shared
        settings.widgetPresentation = isCurrentlyExpanded ? .compact : .focus
        showAndFocus()
    }

    func resize(to presentation: WidgetPresentation, animated: Bool = true) {
        guard !isRecordingAdaptiveSize else { return }
        guard let panel else { return }
        let target = preferredWidgetSize(for: presentation)
        guard abs(panel.contentLayoutRect.width - target.width) > 2
                || abs(panel.contentLayoutRect.height - target.height) > 2 else { return }
        let current = panel.frame
        let targetFrameSize = panel.frameRect(
            forContentRect: NSRect(origin: .zero, size: target)
        ).size
        var targetFrame = NSRect(
            x: current.midX - targetFrameSize.width / 2,
            y: current.midY - targetFrameSize.height / 2,
            width: targetFrameSize.width,
            height: targetFrameSize.height
        )
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            targetFrame.origin.x = min(max(targetFrame.minX, visible.minX), visible.maxX - targetFrame.width)
            targetFrame.origin.y = min(max(targetFrame.minY, visible.minY), visible.maxY - targetFrame.height)
        }
        if animated {
            panel.animator().setFrame(targetFrame, display: true)
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }

    func applySettings(_ settings: SettingsStore) {
        guard let panel else { return }
        panel.alphaValue = settings.widgetOpacity
        panel.ignoresMouseEvents = settings.widgetClickThrough
        panel.isMovableByWindowBackground = !settings.widgetLocked
        panel.collectionBehavior = settings.widgetAllSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.moveToActiveSpace, .fullScreenAuxiliary]

    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let resizedPanel = notification.object as? NSPanel,
              resizedPanel === panel else { return }
        isRecordingAdaptiveSize = true
        SettingsStore.shared.widgetPresentation = .adaptive
        isRecordingAdaptiveSize = false
    }

    private func hideSystemWindowControls(on panel: NSPanel) {
        for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = panel.standardWindowButton(buttonType) else { continue }
            button.isHidden = true
            button.alphaValue = 0
        }
    }

}

func restoredAdaptiveNeedsCompactPreset(_ size: CGSize) -> Bool {
    guard size.width >= 180,
          size.height >= WidgetLayout.minimumCompactHeight else { return true }

    let legacyCompactWidths: [CGFloat] = [320, 360]
    return WidgetLayout(size: size) == .compact
        && legacyCompactWidths.contains { abs(size.width - $0) <= 2 }
}

func preferredWidgetSize(for presentation: WidgetPresentation) -> NSSize {
    switch presentation {
    case .mini: NSSize(width: 144, height: 58)
    case .compact: NSSize(width: 260, height: 138)
    case .focus: NSSize(width: 340, height: 300)
    case .adaptive: NSSize(width: 400, height: 430)
    }
}
