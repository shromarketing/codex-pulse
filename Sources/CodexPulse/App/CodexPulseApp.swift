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
                .preferredColorScheme(settings.theme.colorScheme)
                .frame(minWidth: 940, minHeight: 650)
                .task { state.start() }
        }
        .defaultSize(width: 1080, height: 760)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(state)
                .environmentObject(settings)
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
                .preferredColorScheme(settings.theme.colorScheme)
                .frame(width: 540, height: 430)
        }
    }
}
