import Foundation

struct CodexRouteAssessment: Sendable {
    let model: RouterModel
    let effort: ReasoningEffort
    let confidence: RouterConfidence
    let taskShape: RouterTaskShape
    let needsSplit: Bool
    let rationaleRU: String
    let rationaleEN: String
    let stages: [RouteStage]
}

struct TaskRouter: Sendable {
    func recommend(
        task: String,
        codex: ProviderSnapshot,
        claude: ProviderSnapshot,
        analytics: [ProviderKind: UsageAnalyticsSnapshot] = [:],
        source: RouterSource = .localRules
    ) -> RouteRecommendation {
        let profile = TaskProfile(task: task)
        let route = localRoute(for: profile)
        let provider = selectProvider(for: profile, codex: codex, claude: claude)
        let historicalRange = historicalRange(for: route.model, provider: provider, analytics: analytics)

        return RouteRecommendation(
            model: route.model,
            effort: route.effort,
            provider: provider,
            estimate: estimate(model: route.model, effort: route.effort, needsSplit: profile.needsSplit),
            source: source,
            confidence: profile.confidence,
            taskShape: profile.shape,
            needsSplit: profile.needsSplit,
            stages: localStages(for: profile, primaryModel: route.model),
            rationaleRU: localRationaleRU(for: profile, route: route, source: source),
            rationaleEN: localRationaleEN(for: profile, route: route, source: source),
            estimatedTokensLow: historicalRange?.low,
            estimatedTokensHigh: historicalRange?.high
        )
    }

    func recommend(
        task: String,
        assessment: CodexRouteAssessment,
        codex: ProviderSnapshot,
        claude: ProviderSnapshot,
        analytics: [ProviderKind: UsageAnalyticsSnapshot] = [:]
    ) -> RouteRecommendation {
        let profile = TaskProfile(task: task)
        let floor = safetyFloor(for: profile)
        let guardedModel = maxModel(assessment.model, floor.model)
        let guardedEffort = maxEffort(assessment.effort, floor.effort)
        let wasRaised = guardedModel != assessment.model || guardedEffort != assessment.effort
        let needsSplit = assessment.needsSplit || profile.needsSplit
        let provider = selectProvider(for: profile, codex: codex, claude: claude)
        let historicalRange = historicalRange(for: guardedModel, provider: provider, analytics: analytics)
        let fallbackStages = localStages(for: profile, primaryModel: guardedModel, force: needsSplit)
        let proposedStages = needsSplit
            ? (assessment.stages.count >= 2 ? assessment.stages : fallbackStages)
            : []
        let stages = proposedStages.enumerated().map { index, stage in
            guard index == 0 else { return stage }
            return RouteStage(
                model: maxModel(stage.model, guardedModel),
                effort: maxEffort(stage.effort, guardedEffort),
                titleRU: stage.titleRU,
                titleEN: stage.titleEN
            )
        }
        let guardrailRU = wasRaised
            ? " Pulse поднял минимальный уровень из-за масштаба, риска или необходимости проверки."
            : ""
        let guardrailEN = wasRaised
            ? " Pulse raised the minimum route because of scale, risk, or verification needs."
            : ""

        return RouteRecommendation(
            model: guardedModel,
            effort: guardedEffort,
            provider: provider,
            estimate: estimate(model: guardedModel, effort: guardedEffort, needsSplit: needsSplit),
            source: .codexAI,
            confidence: assessment.confidence,
            taskShape: profile.needsSplit ? profile.shape : assessment.taskShape,
            needsSplit: needsSplit,
            stages: Array(stages.prefix(4)),
            rationaleRU: limited(assessment.rationaleRU, fallback: localRationaleRU(for: profile, route: floor, source: .localRules)) + guardrailRU,
            rationaleEN: limited(assessment.rationaleEN, fallback: localRationaleEN(for: profile, route: floor, source: .localRules)) + guardrailEN,
            estimatedTokensLow: historicalRange?.low,
            estimatedTokensHigh: historicalRange?.high
        )
    }

    private func localRoute(for profile: TaskProfile) -> (model: RouterModel, effort: ReasoningEffort) {
        if profile.requiresFrontier {
            return (.sol, profile.isHighStakes ? .high : .medium)
        }
        if profile.needsSplit || profile.isFullBuild {
            return (.terra, .high)
        }
        if profile.isComplex {
            return (.terra, .medium)
        }
        return (.luna, .low)
    }

    private func safetyFloor(for profile: TaskProfile) -> (model: RouterModel, effort: ReasoningEffort) {
        if profile.requiresFrontier { return (.sol, .high) }
        if profile.needsSplit || profile.isFullBuild { return (.terra, .high) }
        if profile.isComplex { return (.terra, .medium) }
        return (.luna, .low)
    }

    private func selectProvider(
        for profile: TaskProfile,
        codex: ProviderSnapshot,
        claude: ProviderSnapshot
    ) -> ProviderKind {
        if claude.state != .connected { return .codex }
        if codex.state != .connected { return .claude }

        let codexRemaining = codex.remainingPercent ?? -1
        let claudeRemaining = claude.remainingPercent ?? -1
        if profile.prefersCodex, profile.shape == .quick, codexRemaining >= 15 { return .codex }
        if profile.prefersClaude, claudeRemaining >= codexRemaining - 12 { return .claude }
        if profile.prefersCodex, codexRemaining >= claudeRemaining - 15 { return .codex }
        return codexRemaining >= claudeRemaining ? .codex : .claude
    }

    private func estimate(model: RouterModel, effort: ReasoningEffort, needsSplit: Bool) -> UsageEstimate {
        if needsSplit || model == .sol || effort == .high || effort == .xhigh { return .high }
        if model == .terra || effort == .medium { return .medium }
        return .low
    }

    private func localStages(for profile: TaskProfile, primaryModel: RouterModel, force: Bool = false) -> [RouteStage] {
        guard profile.needsSplit || force else { return [] }
        return [
            RouteStage(
                model: maxModel(primaryModel, .terra),
                effort: .high,
                titleRU: "Спланировать выборку, ограничения, формат результата и критерии готовности",
                titleEN: "Plan the sample, constraints, output format, and completion criteria"
            ),
            RouteStage(
                model: .luna,
                effort: .low,
                titleRU: "Выполнить повторяемую пакетную часть после проверки на небольшой выборке",
                titleEN: "Run the repeatable batch stage after validating a small sample"
            ),
            RouteStage(
                model: .terra,
                effort: .medium,
                titleRU: "Проверить полноту, ошибки, дубликаты и итоговые артефакты",
                titleEN: "Verify completeness, errors, duplicates, and final artifacts"
            ),
        ]
    }

    private func localRationaleRU(
        for profile: TaskProfile,
        route: (model: RouterModel, effort: ReasoningEffort),
        source: RouterSource
    ) -> String {
        let basis: String
        if profile.needsSplit {
            basis = "Это масштабная многоэтапная задача с внешними действиями: сначала нужен план и пробная выборка, затем пакетное выполнение и отдельная проверка."
        } else if profile.requiresFrontier {
            basis = "Задача требует сложного профессионального рассуждения и тщательной проверки, поэтому экономичная модель здесь создаёт лишний риск."
        } else if profile.isFullBuild {
            basis = "Полная сборка продукта требует структуры, реализации и проверки, поэтому нужен сбалансированный маршрут с высоким effort."
        } else if profile.isComplex {
            basis = "В задаче несколько зависимых решений или требуется исследование, поэтому выбран баланс качества и расхода."
        } else {
            basis = "Задача узкая и проверяемая, поэтому достаточно быстрой экономичной модели с низким effort."
        }
        let fallback = source == .localFallback ? " AI-анализ сейчас недоступен, поэтому показан безопасный локальный маршрут." : ""
        return "\(basis) Основной следующий шаг: \(route.model.rawValue), effort \(route.effort.rawValue).\(fallback) Ничего не запускается автоматически."
    }

    private func localRationaleEN(
        for profile: TaskProfile,
        route: (model: RouterModel, effort: ReasoningEffort),
        source: RouterSource
    ) -> String {
        let basis: String
        if profile.needsSplit {
            basis = "This is a large multi-stage task with external actions: plan and validate a sample first, then run the batch and verify it separately."
        } else if profile.requiresFrontier {
            basis = "The task needs difficult professional reasoning and careful verification, so an economical model would add avoidable risk."
        } else if profile.isFullBuild {
            basis = "A full product build needs structure, implementation, and verification, so it benefits from a balanced route with high effort."
        } else if profile.isComplex {
            basis = "The task contains dependent decisions or research, so the route balances quality and usage."
        } else {
            basis = "The task is narrow and easy to verify, so a fast economical model with low effort is enough."
        }
        let fallback = source == .localFallback ? " AI analysis is unavailable right now, so Pulse is showing the safe local route." : ""
        return "\(basis) Primary next step: \(route.model.rawValue), effort \(route.effort.rawValue).\(fallback) Nothing starts automatically."
    }

    private func historicalRange(
        for model: RouterModel,
        provider: ProviderKind,
        analytics: [ProviderKind: UsageAnalyticsSnapshot]
    ) -> (low: Int64, high: Int64)? {
        let values = analytics[provider]?.recentReceipts.compactMap { receipt -> Int64? in
            guard receipt.primaryModel?.lowercased().contains(model.rawValue.lowercased()) == true,
                  receipt.totalTokens > 0 else { return nil }
            return receipt.totalTokens
        }.sorted() ?? []
        return percentileRange(values)
    }

    private func percentileRange(_ values: [Int64]) -> (low: Int64, high: Int64)? {
        guard values.count >= 3 else { return nil }
        let lowIndex = Int(Double(values.count - 1) * 0.25)
        let highIndex = Int(Double(values.count - 1) * 0.75)
        return (values[lowIndex], values[max(lowIndex, highIndex)])
    }

    private func maxModel(_ left: RouterModel, _ right: RouterModel) -> RouterModel {
        modelRank(left) >= modelRank(right) ? left : right
    }

    private func modelRank(_ value: RouterModel) -> Int {
        switch value {
        case .luna: 0
        case .terra: 1
        case .sol: 2
        }
    }

    private func maxEffort(_ left: ReasoningEffort, _ right: ReasoningEffort) -> ReasoningEffort {
        effortRank(left) >= effortRank(right) ? left : right
    }

    private func effortRank(_ value: ReasoningEffort) -> Int {
        switch value {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .xhigh: 3
        }
    }

    private func limited(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(700))
    }
}

private struct TaskProfile {
    let normalized: String
    let wordCount: Int
    let shape: RouterTaskShape
    let isHighStakes: Bool
    let requiresFrontier: Bool
    let isFullBuild: Bool
    let isComplex: Bool
    let needsSplit: Bool
    let prefersClaude: Bool
    let prefersCodex: Bool
    let confidence: RouterConfidence

    init(task: String) {
        normalized = task.lowercased()
        wordCount = normalized.split(whereSeparator: { $0.isWhitespace }).count

        let security = Self.hasAny(normalized, ["security", "vulnerability", "threat model", "безопас", "уязвим", "пентест"])
        let architecture = Self.hasAny(normalized, ["architecture", "architectural", "архитект", "system design", "системный дизайн"])
        let highStakes = Self.hasAny(normalized, ["production", "deploy", "migration", "delete", "payment", "legal", "financial", "medical", "продакш", "деплой", "миграц", "удал", "платеж", "юрид", "финанс", "медицин"])
        let research = Self.hasAny(normalized, ["research", "analyze", "compare", "audit", "исслед", "анализ", "сравн", "аудит", "изучить"])
        let writing = Self.hasAny(normalized, ["write", "rewrite", "article", "copy", "strategy", "текст", "статья", "редак", "стратег", "сценар"])
        let coding = Self.hasAny(normalized, ["code", "bug", "api", "swift", "python", "код", "баг", "разработ", "реализ", "интеграц", "скрипт"])
        let design = Self.hasAny(normalized, ["design", "layout", "interface", "ui", "ux", "дизайн", "интерфейс", "макет"])
        let documents = Self.hasAny(normalized, ["document", "presentation", "spreadsheet", "pdf", "документ", "презентац", "таблиц"])
        let review = Self.hasAny(normalized, ["review", "verify", "test", "qa", "провер", "тест", "ревью"])
        let automation = Self.hasAny(normalized, ["automate", "scrape", "crawl", "download", "batch", "автомат", "парс", "скач", "краул", "пакет"])
        let external = Self.hasAny(normalized, ["site", "website", "web", "url", "internet", "сайт", "интернет", "ссылка"])
        let buildObject = Self.hasAny(normalized, ["website", "site", "app", "product", "сайт", "прилож", "продукт", "сервис"])
        let creationVerb = Self.hasAny(normalized, ["create", "build", "develop", "implement", "from scratch", "созд", "сделать", "разработ", "реализ", "с нуля"])
        let quick = Self.hasAny(normalized, ["typo", "rename", "translate", "format", "опечат", "переимен", "перевед", "форматир"])
        let boundedEdit = Self.hasAny(normalized, ["edit", "fix", "correct", "change", "исправ", "поправ", "замен", "измен"])
        let numericScale = Self.maximumNumber(in: normalized)
        let largeData = Self.hasAny(normalized, [" gb", "gb ", "гб", "gigabyte", "гигабайт", "тысяч", "million", "миллион"])
        let bulkWord = Self.hasAny(normalized, ["all sites", "many files", "hundreds", "bulk", "batch", "все сайты", "много файлов", "сотн", "массов", "пакет"])
        let multipleActions = Self.actionCount(in: normalized) >= 2

        isHighStakes = highStakes || security
        requiresFrontier = architecture || security || (highStakes && (coding || automation || review))
        isFullBuild = buildObject && creationVerb
        needsSplit = (automation || research) && (largeData || bulkWord || (numericScale ?? 0) >= 50) && external
            || (isFullBuild && wordCount > 28)
            || (multipleActions && wordCount > 45)
        let lightweightVerification = review && boundedEdit && !research && !coding && !design && !documents && !automation && !highStakes && wordCount <= 14
        isComplex = research || coding || design || documents || automation || isFullBuild || wordCount > 24 || multipleActions || (review && !lightweightVerification)
        prefersClaude = writing && !coding && !automation && !lightweightVerification
        prefersCodex = coding || design || automation || external || lightweightVerification

        if architecture || security {
            shape = .architecture
        } else if automation || (external && (numericScale ?? 0) >= 20) {
            shape = .automation
        } else if coding || isFullBuild {
            shape = .coding
        } else if design {
            shape = .design
        } else if research {
            shape = .research
        } else if quick || lightweightVerification || wordCount <= 7 {
            shape = .quick
        } else if writing {
            shape = .writing
        } else if documents {
            shape = .documents
        } else if review {
            shape = .review
        } else {
            shape = .other
        }

        if requiresFrontier || needsSplit || quick {
            confidence = .high
        } else if isComplex || wordCount >= 8 {
            confidence = .medium
        } else {
            confidence = .low
        }
    }

    private static func hasAny(_ value: String, _ signals: [String]) -> Bool {
        signals.contains(where: value.contains)
    }

    private static func maximumNumber(in value: String) -> Double? {
        guard let expression = try? NSRegularExpression(pattern: #"\b\d+(?:[.,]\d+)?\b"#) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: value) else { return nil }
            return Double(value[swiftRange].replacingOccurrences(of: ",", with: "."))
        }.max()
    }

    private static func actionCount(in value: String) -> Int {
        let signals = ["create", "build", "implement", "design", "research", "analyze", "download", "verify", "созд", "сделать", "разработ", "реализ", "спроект", "исслед", "проанализ", "скач", "провер"]
        return signals.reduce(0) { count, signal in
            count + max(0, value.components(separatedBy: signal).count - 1)
        }
    }
}
