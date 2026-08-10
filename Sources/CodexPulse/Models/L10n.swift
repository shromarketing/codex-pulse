import Foundation

enum L10n {
    static func text(_ language: AppLanguage, ru: String, en: String) -> String {
        language == .russian ? ru : en
    }

    static func themeTitle(_ value: AppTheme, language: AppLanguage) -> String {
        switch value {
        case .system: text(language, ru: "Системная", en: "System")
        case .light: text(language, ru: "Светлая", en: "Light")
        case .dark: text(language, ru: "Тёмная", en: "Dark")
        }
    }

    static func menuStyleTitle(_ value: MenuBarStyle, language: AppLanguage) -> String {
        switch value {
        case .pulse: text(language, ru: "Пульс", en: "Pulse")
        case .percentage: text(language, ru: "Процент", en: "Percent")
        case .dual: text(language, ru: "Два сервиса", en: "Two services")
        }
    }

    static func estimateTitle(_ value: UsageEstimate, language: AppLanguage) -> String {
        switch value {
        case .low: text(language, ru: "Низкий расход", en: "Low usage")
        case .medium: text(language, ru: "Средний расход", en: "Moderate usage")
        case .high: text(language, ru: "Высокий расход", en: "High usage")
        }
    }
}
