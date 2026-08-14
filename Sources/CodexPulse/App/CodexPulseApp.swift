import AppKit
import SwiftUI

@main
struct CodexPulseApp: App {
    @StateObject private var state = AppState.shared
    @StateObject private var settings = SettingsStore.shared

    var body: some Scene {
        WindowGroup("Codex Pulse", id: "dashboard") {
            DashboardView()
                .environmentObject(state)
                .environmentObject(settings)
                .environment(\.locale, settings.language.locale)
                .preferredColorScheme(settings.theme.colorScheme)
                .frame(minWidth: 1040, minHeight: 700)
                .task { state.start() }
        }
        .defaultSize(width: 1180, height: 800)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(state)
                .environmentObject(settings)
                .environment(\.locale, settings.language.locale)
                .preferredColorScheme(settings.theme.colorScheme)
        } label: {
            MenuBarLabelView()
                .environmentObject(state)
                .environmentObject(settings)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(state)
                .environmentObject(settings)
                .environment(\.locale, settings.language.locale)
                .preferredColorScheme(settings.theme.colorScheme)
                .frame(width: 620, height: 720)
        }
    }
}
