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
        case .smart: text(language, ru: "Умный", en: "Smart")
        case .today: text(language, ru: "Расход сегодня", en: "Today usage")
        case .pace: text(language, ru: "Темп", en: "Pace")
        }
    }

    static func experienceTitle(_ value: ExperienceMode, language: AppLanguage) -> String {
        switch value {
        case .simple: text(language, ru: "Простой", en: "Simple")
        case .pro: text(language, ru: "Pro", en: "Pro")
        }
    }

    static func widgetTitle(_ value: WidgetPresentation, language: AppLanguage) -> String {
        switch value {
        case .mini: text(language, ru: "Мини", en: "Mini")
        case .compact: text(language, ru: "Компакт", en: "Compact")
        case .focus: text(language, ru: "Фокус", en: "Focus")
        case .adaptive: text(language, ru: "Адаптивный", en: "Adaptive")
        }
    }

    static func categoryTitle(_ value: TaskCategory, language: AppLanguage) -> String {
        switch value {
        case .coding: text(language, ru: "Код", en: "Code")
        case .research: text(language, ru: "Исследования", en: "Research")
        case .design: text(language, ru: "Дизайн", en: "Design")
        case .documents: text(language, ru: "Документы", en: "Documents")
        case .review: text(language, ru: "Проверка/QA", en: "Review & QA")
        case .automation: text(language, ru: "Автоматизация", en: "Automation")
        case .other: text(language, ru: "Другое", en: "Other")
        }
    }

    static func estimateTitle(_ value: UsageEstimate, language: AppLanguage) -> String {
        switch value {
        case .low: text(language, ru: "Низкий расход", en: "Low usage")
        case .medium: text(language, ru: "Средний расход", en: "Moderate usage")
        case .high: text(language, ru: "Высокий расход", en: "High usage")
        }
    }

    static func routeModeTitle(_ value: RouterAnalysisMode, language: AppLanguage) -> String {
        switch value {
        case .ai: text(language, ru: "AI-анализ", en: "AI analysis")
        case .local: text(language, ru: "Локально", en: "Local")
        }
    }

    static func routeSourceTitle(_ value: RouterSource, language: AppLanguage) -> String {
        switch value {
        case .codexAI: text(language, ru: "Проверено Codex AI", en: "Checked by Codex AI")
        case .localRules: text(language, ru: "Локальный анализ", en: "Local analysis")
        case .localFallback: text(language, ru: "Локальный резерв", en: "Local fallback")
        }
    }

    static func routeConfidenceTitle(_ value: RouterConfidence, language: AppLanguage) -> String {
        switch value {
        case .low: text(language, ru: "низкая", en: "low")
        case .medium: text(language, ru: "средняя", en: "medium")
        case .high: text(language, ru: "высокая", en: "high")
        }
    }

    static func routeTaskShapeTitle(_ value: RouterTaskShape, language: AppLanguage) -> String {
        switch value {
        case .quick: text(language, ru: "Быстрая задача", en: "Quick task")
        case .writing: text(language, ru: "Текст", en: "Writing")
        case .research: text(language, ru: "Исследование", en: "Research")
        case .coding: text(language, ru: "Разработка", en: "Coding")
        case .design: text(language, ru: "Дизайн", en: "Design")
        case .documents: text(language, ru: "Документы", en: "Documents")
        case .automation: text(language, ru: "Масштабная автоматизация", en: "Large automation")
        case .architecture: text(language, ru: "Архитектура / высокий риск", en: "Architecture / high stakes")
        case .review: text(language, ru: "Проверка", en: "Review")
        case .other: text(language, ru: "Смешанная задача", en: "Mixed task")
        }
    }
}
