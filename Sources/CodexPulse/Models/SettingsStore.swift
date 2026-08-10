import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    @Published var menuBarStyle: MenuBarStyle {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: Keys.menuBarStyle) }
    }

    @Published var showFloatingWidget: Bool {
        didSet { defaults.set(showFloatingWidget, forKey: Keys.showFloatingWidget) }
    }

    @Published var refreshMinutes: Int {
        didSet { defaults.set(refreshMinutes, forKey: Keys.refreshMinutes) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let language = "app.language"
        static let theme = "app.theme"
        static let menuBarStyle = "menubar.style"
        static let showFloatingWidget = "widget.floating"
        static let refreshMinutes = "refresh.minutes"
    }

    private init() {
        language = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:)) ?? .systemDefault
        theme = defaults.string(forKey: Keys.theme).flatMap(AppTheme.init(rawValue:)) ?? .system
        menuBarStyle = defaults.string(forKey: Keys.menuBarStyle).flatMap(MenuBarStyle.init(rawValue:)) ?? .percentage
        showFloatingWidget = defaults.object(forKey: Keys.showFloatingWidget) as? Bool ?? true
        let storedRefresh = defaults.integer(forKey: Keys.refreshMinutes)
        refreshMinutes = storedRefresh > 0 ? storedRefresh : 5
    }
}
