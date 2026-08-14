import Foundation

enum QuotaHistoryScope: String, Codable, Hashable, Sendable {
    case session
    case weekly
    case modelWeekly
    case other
}

struct QuotaHistorySample: Hashable, Sendable {
    let provider: ProviderKind
    let windowID: String
    let scope: QuotaHistoryScope
    let title: String?
    let usedPercent: Double
    let resetsAt: Date?
    let windowMinutes: Int?
}

struct QuotaHistoryPoint: Codable, Hashable, Identifiable, Sendable {
    let date: Date
    let provider: ProviderKind
    let windowID: String
    let scope: QuotaHistoryScope
    let title: String?
    let usedPercent: Double
    let resetsAt: Date?
    let windowMinutes: Int?

    var id: String {
        "\(provider.rawValue)-\(windowID)-\(date.timeIntervalSince1970)"
    }

    var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}

struct TokenTotals: Codable, Hashable, Sendable {
    let inputTokens: Int64
    let cacheReadTokens: Int64
    let outputTokens: Int64
    let totalTokens: Int64
    let totalCost: Double?

    static let zero = TokenTotals(
        inputTokens: 0,
        cacheReadTokens: 0,
        outputTokens: 0,
        totalTokens: 0,
        totalCost: nil
    )
}

struct ModelUsage: Codable, Hashable, Identifiable, Sendable {
    let modelName: String
    let totalTokens: Int64
    let cost: Double?

    var id: String { modelName }
}

struct DailyTokenUsage: Codable, Hashable, Identifiable, Sendable {
    let date: String
    let inputTokens: Int64
    let cacheReadTokens: Int64
    let outputTokens: Int64
    let totalTokens: Int64
    let totalCost: Double?
    let modelBreakdowns: [ModelUsage]

    var id: String { date }

    var parsedDate: Date? {
        Self.dayFormatter.date(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()
}

struct ProjectUsage: Codable, Hashable, Identifiable, Sendable {
    let name: String
    let path: String
    let totalTokens: Int64
    let totalCost: Double?
    let modelBreakdowns: [ModelUsage]
    let daily: [DailyTokenUsage]

    var id: String { path.isEmpty ? name : path }
    var displayPath: String { path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
}

struct AccountUsageSummary: Codable, Hashable, Sendable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSec: Int64?
    let currentStreakDays: Int64?
    let longestStreakDays: Int64?

    static let empty = AccountUsageSummary(
        lifetimeTokens: nil,
        peakDailyTokens: nil,
        longestRunningTurnSec: nil,
        currentStreakDays: nil,
        longestStreakDays: nil
    )
}

struct AccountDailyUsage: Codable, Hashable, Identifiable, Sendable {
    let startDate: String
    let tokens: Int64
    var id: String { startDate }

    var parsedDate: Date? {
        Self.dayFormatter.date(from: startDate)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()
}

struct UsageAnalyticsSnapshot: Codable, Hashable, Sendable {
    let provider: ProviderKind
    let currencyCode: String
    let source: String
    let updatedAt: Date
    let totals: TokenTotals
    let daily: [DailyTokenUsage]
    let projects: [ProjectUsage]
    let accountSummary: AccountUsageSummary?
    let accountDaily: [AccountDailyUsage]

    static func empty(_ provider: ProviderKind) -> UsageAnalyticsSnapshot {
        UsageAnalyticsSnapshot(
            provider: provider,
            currencyCode: "USD",
            source: "",
            updatedAt: .now,
            totals: .zero,
            daily: [],
            projects: [],
            accountSummary: nil,
            accountDaily: []
        )
    }

    func filtered(to period: UsagePeriod, now: Date = .now, calendar: Calendar = .current) -> UsageAnalyticsSnapshot {
        let end = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -(period.rawValue - 1), to: end) else {
            return self
        }
        let components = calendar.dateComponents([.year, .month, .day], from: cutoff)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return self
        }
        let cutoffKey = String(format: "%04d-%02d-%02d", year, month, day)

        let filteredDaily = daily.filter { $0.date >= cutoffKey }
        let filteredProjects = projects.compactMap { project -> ProjectUsage? in
            let projectDays = project.daily.filter { $0.date >= cutoffKey }
            guard !projectDays.isEmpty else { return nil }
            let projectTotals = Self.totals(for: projectDays)
            return ProjectUsage(
                name: project.name,
                path: project.path,
                totalTokens: projectTotals.totalTokens,
                totalCost: projectTotals.totalCost,
                modelBreakdowns: Self.models(for: projectDays),
                daily: projectDays
            )
        }
        let filteredAccountDaily = accountDaily.filter { $0.startDate >= cutoffKey }

        return UsageAnalyticsSnapshot(
            provider: provider,
            currencyCode: currencyCode,
            source: source,
            updatedAt: updatedAt,
            totals: Self.totals(for: filteredDaily),
            daily: filteredDaily,
            projects: filteredProjects,
            accountSummary: accountSummary,
            accountDaily: filteredAccountDaily
        )
    }

    var modelTotals: [ModelUsage] {
        var totals: [String: (tokens: Int64, cost: Double)] = [:]
        var modelsWithCost = Set<String>()
        for day in daily {
            for model in day.modelBreakdowns {
                totals[model.modelName, default: (0, 0)].tokens += model.totalTokens
                if let cost = model.cost {
                    totals[model.modelName, default: (0, 0)].cost += cost
                    modelsWithCost.insert(model.modelName)
                }
            }
        }
        return totals.map { key, value in
            ModelUsage(
                modelName: key,
                totalTokens: value.tokens,
                cost: modelsWithCost.contains(key) ? value.cost : nil
            )
        }
        .sorted { $0.totalTokens > $1.totalTokens }
    }

    var recentReceipts: [TaskReceipt] {
        projects.flatMap { project in
            project.daily.map { day in
                TaskReceipt(
                    provider: provider,
                    projectName: project.name,
                    projectPath: project.path,
                    date: day.parsedDate ?? updatedAt,
                    totalTokens: day.totalTokens,
                    inputTokens: day.inputTokens,
                    cachedTokens: day.cacheReadTokens,
                    outputTokens: day.outputTokens,
                    estimatedCost: day.totalCost,
                    primaryModel: day.modelBreakdowns.max(by: { $0.totalTokens < $1.totalTokens })?.modelName,
                    category: TaskCategory.classify(project.name + " " + project.path)
                )
            }
        }
        .sorted { $0.date > $1.date }
    }

    private static func totals(for days: [DailyTokenUsage]) -> TokenTotals {
        let costs = days.compactMap(\.totalCost)
        return TokenTotals(
            inputTokens: days.reduce(0) { $0 + $1.inputTokens },
            cacheReadTokens: days.reduce(0) { $0 + $1.cacheReadTokens },
            outputTokens: days.reduce(0) { $0 + $1.outputTokens },
            totalTokens: days.reduce(0) { $0 + $1.totalTokens },
            totalCost: costs.isEmpty ? nil : costs.reduce(0, +)
        )
    }

    private static func models(for days: [DailyTokenUsage]) -> [ModelUsage] {
        var totals: [String: (tokens: Int64, cost: Double, hasCost: Bool)] = [:]
        for model in days.flatMap(\.modelBreakdowns) {
            var total = totals[model.modelName] ?? (0, 0, false)
            total.tokens += model.totalTokens
            if let cost = model.cost {
                total.cost += cost
                total.hasCost = true
            }
            totals[model.modelName] = total
        }
        return totals.map { name, total in
            ModelUsage(
                modelName: name,
                totalTokens: total.tokens,
                cost: total.hasCost ? total.cost : nil
            )
        }
        .sorted { $0.totalTokens > $1.totalTokens }
    }
}

enum TaskCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case coding
    case research
    case design
    case documents
    case review
    case automation
    case other

    var id: String { rawValue }

    static func classify(_ source: String) -> TaskCategory {
        let value = source.lowercased()
        if ["design", "figma", "site", "web", "дизайн", "лендинг", "сайт"].contains(where: value.contains) { return .design }
        if ["research", "analysis", "study", "исслед", "анализ", "обучен"].contains(where: value.contains) { return .research }
        if ["review", "audit", "ревью", "аудит", "провер"].contains(where: value.contains) { return .review }
        if ["document", "slides", "presentation", "документ", "презентац", "договор"].contains(where: value.contains) { return .documents }
        if ["automation", "script", "автомат", "chatbot", "чат-бот", "telegram-bot"].contains(where: value.contains) { return .automation }
        if ["code", "api", "app", "swift", "python", "github", "код", "прилож"].contains(where: value.contains) { return .coding }
        return .other
    }
}

struct TaskReceipt: Hashable, Identifiable, Sendable {
    let provider: ProviderKind
    let projectName: String
    let projectPath: String
    let date: Date
    let totalTokens: Int64
    let inputTokens: Int64
    let cachedTokens: Int64
    let outputTokens: Int64
    let estimatedCost: Double?
    let primaryModel: String?
    let category: TaskCategory

    var id: String { "\(provider.rawValue)-\(projectPath)-\(date.timeIntervalSince1970)" }
}

struct PaceInsight: Hashable, Sendable {
    let level: HealthLevel
    let burnPercentPerDay: Double?
    let safePercentToday: Double?
    let projectedExhaustion: Date?
    let resetAt: Date?

    static let unknown = PaceInsight(
        level: .unknown,
        burnPercentPerDay: nil,
        safePercentToday: nil,
        projectedExhaustion: nil,
        resetAt: nil
    )
}

enum ServiceHealthState: String, Codable, Sendable {
    case operational
    case degraded
    case outage
    case unknown
}

struct ServiceHealthSnapshot: Identifiable, Sendable {
    let provider: ProviderKind
    let state: ServiceHealthState
    let message: String
    let updatedAt: Date
    var id: ProviderKind { provider }
}
