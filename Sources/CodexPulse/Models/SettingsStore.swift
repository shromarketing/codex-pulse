import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var language: AppLanguage { didSet { set(language.rawValue, Keys.language) } }
    @Published var theme: AppTheme { didSet { set(theme.rawValue, Keys.theme) } }
    @Published var experienceMode: ExperienceMode { didSet { set(experienceMode.rawValue, Keys.experienceMode) } }
    @Published var menuBarStyle: MenuBarStyle { didSet { set(menuBarStyle.rawValue, Keys.menuBarStyle) } }
    @Published var showFloatingWidget: Bool { didSet { set(showFloatingWidget, Keys.showFloatingWidget) } }
    @Published var widgetPresentation: WidgetPresentation {
        didSet {
            set(widgetPresentation.rawValue, Keys.widgetPresentation)
            FloatingPanelController.shared.resize(to: widgetPresentation)
        }
    }
    @Published var widgetOpacity: Double {
        didSet {
            set(widgetOpacity, Keys.widgetOpacity)
            FloatingPanelController.shared.applySettings(self)
        }
    }
    @Published var widgetLocked: Bool {
        didSet {
            set(widgetLocked, Keys.widgetLocked)
            FloatingPanelController.shared.applySettings(self)
        }
    }
    @Published var widgetClickThrough: Bool {
        didSet {
            set(widgetClickThrough, Keys.widgetClickThrough)
            FloatingPanelController.shared.applySettings(self)
        }
    }
    @Published var widgetAllSpaces: Bool {
        didSet {
            set(widgetAllSpaces, Keys.widgetAllSpaces)
            FloatingPanelController.shared.applySettings(self)
        }
    }
    @Published var refreshMinutes: Int { didSet { set(refreshMinutes, Keys.refreshMinutes) } }
    @Published var analyticsEnabled: Bool { didSet { set(analyticsEnabled, Keys.analyticsEnabled) } }
    @Published var usagePeriod: UsagePeriod { didSet { set(usagePeriod.rawValue, Keys.usagePeriod) } }
    @Published var notificationsEnabled: Bool { didSet { set(notificationsEnabled, Keys.notificationsEnabled) } }
    @Published var predictiveAlerts: Bool { didSet { set(predictiveAlerts, Keys.predictiveAlerts) } }
    @Published var notificationSound: Bool { didSet { set(notificationSound, Keys.notificationSound) } }
    @Published var warningThreshold: Int { didSet { set(warningThreshold, Keys.warningThreshold) } }
    @Published var criticalThreshold: Int { didSet { set(criticalThreshold, Keys.criticalThreshold) } }
    @Published var launchAtLogin: Bool {
        didSet {
            if isRestoringLaunchAtLogin {
                set(launchAtLogin, Keys.launchAtLogin)
                return
            }
            if let message = LaunchAtLoginService.apply(enabled: launchAtLogin) {
                launchAtLoginError = message
                isRestoringLaunchAtLogin = true
                launchAtLogin = oldValue
                isRestoringLaunchAtLogin = false
                return
            }
            launchAtLoginError = ""
            set(launchAtLogin, Keys.launchAtLogin)
        }
    }
    @Published var statusChecksEnabled: Bool { didSet { set(statusChecksEnabled, Keys.statusChecksEnabled) } }
    @Published var showEstimatedCost: Bool { didSet { set(showEstimatedCost, Keys.showEstimatedCost) } }
    @Published var showUnavailableProviders: Bool { didSet { set(showUnavailableProviders, Keys.showUnavailableProviders) } }
    @Published var claudeUsageSource: ClaudeUsageSource { didSet { set(claudeUsageSource.rawValue, Keys.claudeUsageSource) } }
    @Published var claudeBrowserCookieImportAllowed: Bool {
        didSet { set(claudeBrowserCookieImportAllowed, Keys.claudeBrowserCookieImportAllowed) }
    }
    @Published private(set) var launchAtLoginError = ""

    private let defaults = UserDefaults.standard
    private var isRestoringLaunchAtLogin = false

    private enum Keys {
        static let language = "app.language"
        static let theme = "app.theme"
        static let experienceMode = "app.experienceMode"
        static let menuBarStyle = "menubar.style"
        static let showFloatingWidget = "widget.floating"
        static let widgetPresentation = "widget.presentation"
        static let widgetOpacity = "widget.opacity"
        static let widgetLocked = "widget.locked"
        static let widgetClickThrough = "widget.clickThrough"
        static let widgetAllSpaces = "widget.allSpaces"
        static let refreshMinutes = "refresh.minutes"
        static let analyticsEnabled = "analytics.enabled"
        static let usagePeriod = "analytics.period"
        static let notificationsEnabled = "notifications.enabled"
        static let predictiveAlerts = "notifications.predictive"
        static let notificationSound = "notifications.sound"
        static let warningThreshold = "notifications.warningThreshold"
        static let criticalThreshold = "notifications.criticalThreshold"
        static let launchAtLogin = "app.launchAtLogin"
        static let statusChecksEnabled = "status.enabled"
        static let showEstimatedCost = "cost.visible"
        static let showUnavailableProviders = "providers.showUnavailable"
        static let claudeUsageSource = "providers.claude.source"
        static let claudeBrowserCookieImportAllowed = "providers.claude.browserCookieImportAllowed"
    }

    private init() {
        language = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:)) ?? .systemDefault
        theme = defaults.string(forKey: Keys.theme).flatMap(AppTheme.init(rawValue:)) ?? .system
        experienceMode = defaults.string(forKey: Keys.experienceMode).flatMap(ExperienceMode.init(rawValue:)) ?? .simple
        menuBarStyle = defaults.string(forKey: Keys.menuBarStyle).flatMap(MenuBarStyle.init(rawValue:)) ?? .percentage
        showFloatingWidget = defaults.object(forKey: Keys.showFloatingWidget) as? Bool ?? true
        widgetPresentation = defaults.string(forKey: Keys.widgetPresentation).flatMap(WidgetPresentation.init(rawValue:)) ?? .compact
        widgetOpacity = defaults.object(forKey: Keys.widgetOpacity) as? Double ?? 0.96
        widgetLocked = defaults.object(forKey: Keys.widgetLocked) as? Bool ?? false
        widgetClickThrough = defaults.object(forKey: Keys.widgetClickThrough) as? Bool ?? false
        widgetAllSpaces = defaults.object(forKey: Keys.widgetAllSpaces) as? Bool ?? true
        let storedRefresh = defaults.integer(forKey: Keys.refreshMinutes)
        refreshMinutes = storedRefresh > 0 ? storedRefresh : 5
        analyticsEnabled = defaults.object(forKey: Keys.analyticsEnabled) as? Bool ?? true
        let storedPeriod = defaults.integer(forKey: Keys.usagePeriod)
        usagePeriod = UsagePeriod(rawValue: storedPeriod) ?? .month
        notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
        predictiveAlerts = defaults.object(forKey: Keys.predictiveAlerts) as? Bool ?? true
        notificationSound = defaults.object(forKey: Keys.notificationSound) as? Bool ?? true
        let warning = defaults.integer(forKey: Keys.warningThreshold)
        warningThreshold = warning > 0 ? warning : 50
        let critical = defaults.integer(forKey: Keys.criticalThreshold)
        criticalThreshold = critical > 0 ? critical : 20
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        statusChecksEnabled = defaults.object(forKey: Keys.statusChecksEnabled) as? Bool ?? true
        showEstimatedCost = defaults.object(forKey: Keys.showEstimatedCost) as? Bool ?? true
        showUnavailableProviders = defaults.object(forKey: Keys.showUnavailableProviders) as? Bool ?? false
        claudeUsageSource = defaults.string(forKey: Keys.claudeUsageSource)
            .flatMap(ClaudeUsageSource.init(rawValue:)) ?? .off
        claudeBrowserCookieImportAllowed = defaults.object(forKey: Keys.claudeBrowserCookieImportAllowed) as? Bool ?? false
    }

    private func set(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
