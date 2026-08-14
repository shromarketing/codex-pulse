import CoreGraphics
import Testing
@testable import CodexPulse

@Suite("Floating widget layout")
struct FloatingWidgetLayoutTests {
    @Test("Compact preset reserves enough vertical room for four text rows")
    func compactPresetHasEnoughHeight() {
        let size = preferredWidgetSize(for: .compact)

        #expect(size.width == 260)
        #expect(size.height == 138)
        #expect(size.height >= WidgetLayout.minimumCompactHeight)
        #expect(WidgetLayout(size: size) == .compact)
    }

    @Test("Focus preset opens a taller detail surface")
    func focusPresetUsesFocusLayout() {
        let size = preferredWidgetSize(for: .focus)

        #expect(size.width == 340)
        #expect(size.height == 300)
        #expect(WidgetLayout(size: size) == .focus)
    }

    @Test("The existing wide desktop frame keeps the informative Compact layout")
    func existingWideFrameKeepsCompact() {
        let existingFrame = CGSize(width: 490, height: 108)

        #expect(WidgetLayout(size: existingFrame) == .compact)
        #expect(!restoredAdaptiveNeedsCompactPreset(existingFrame))
    }

    @Test("Only a truly short widget falls back to Mini")
    func flattenedWidgetUsesMini() {
        let flattened = CGSize(width: 490, height: WidgetLayout.minimumCompactHeight - 1)

        #expect(WidgetLayout(size: flattened) == .mini)
        #expect(restoredAdaptiveNeedsCompactPreset(flattened))
    }

    @Test("Legacy default widths migrate to the narrower Compact preset")
    func legacyDefaultsUseNewCompactWidth() {
        #expect(restoredAdaptiveNeedsCompactPreset(CGSize(width: 320, height: 138)))
        #expect(restoredAdaptiveNeedsCompactPreset(CGSize(width: 320, height: 116)))
        #expect(restoredAdaptiveNeedsCompactPreset(CGSize(width: 360, height: 138)))
        #expect(!restoredAdaptiveNeedsCompactPreset(CGSize(width: 320, height: 300)))
        #expect(!restoredAdaptiveNeedsCompactPreset(CGSize(width: 300, height: 138)))
    }

    @Test("Compact widget defaults to Codex and falls back when Claude disconnects")
    func providerSelectionHasSafeFallback() {
        #expect(resolvedWidgetProvider(.codex, claudeState: .connected) == .codex)
        #expect(resolvedWidgetProvider(.claude, claudeState: .connected) == .claude)
        #expect(resolvedWidgetProvider(.claude, claudeState: .loading) == .codex)
        #expect(resolvedWidgetProvider(.claude, claudeState: .unavailable) == .codex)
    }
}
