import Foundation

struct TaskRouter: Sendable {
    func recommend(
        task: String,
        codex: ProviderSnapshot,
        claude: ProviderSnapshot
    ) -> RouteRecommendation {
        let normalized = task.lowercased()
        let wordCount = normalized.split(whereSeparator: { $0.isWhitespace }).count

        let hardSignals = ["security", "architecture", "migration", "race condition", "vulnerability", "безопас", "архитект", "миграц", "уязвим", "рефакторинг"]
        let mediumSignals = ["research", "analyze", "compare", "document", "presentation", "debug", "исслед", "анализ", "сравн", "документ", "презентац", "отлад"]
        let writingSignals = ["write", "rewrite", "copy", "article", "strategy", "текст", "статья", "редак", "стратег"]
        let codingSignals = ["code", "bug", "build", "implement", "api", "swift", "python", "код", "баг", "разработ", "реализ", "интеграц"]

        let isHard = hardSignals.contains(where: normalized.contains)
        let isMedium = mediumSignals.contains(where: normalized.contains) || wordCount > 22
        let prefersClaude = writingSignals.contains(where: normalized.contains)
        let prefersCodex = codingSignals.contains(where: normalized.contains)

        let model: RouterModel = isHard ? .sol : (isMedium ? .terra : .luna)
        let effort: ReasoningEffort = isHard ? .high : (isMedium ? .medium : .low)
        let estimate: UsageEstimate = isHard ? .high : (isMedium ? .medium : .low)

        let codexRemaining = codex.remainingPercent ?? -1
        let claudeRemaining = claude.remainingPercent ?? -1
        let provider: ProviderKind
        if claude.state != .connected {
            provider = .codex
        } else if codex.state != .connected {
            provider = .claude
        } else if prefersClaude, claudeRemaining >= codexRemaining - 12 {
            provider = .claude
        } else if prefersCodex, codexRemaining >= claudeRemaining - 15 {
            provider = .codex
        } else {
            provider = codexRemaining >= claudeRemaining ? .codex : .claude
        }

        let rationaleRU = "Выбран баланс сложности задачи, доступного лимита и специализации сервиса. Ничего не запускается автоматически."
        let rationaleEN = "Balanced by task complexity, available quota, and provider fit. Nothing starts automatically."
        return RouteRecommendation(
            model: model,
            effort: effort,
            provider: provider,
            estimate: estimate,
            rationaleRU: rationaleRU,
            rationaleEN: rationaleEN
        )
    }
}
