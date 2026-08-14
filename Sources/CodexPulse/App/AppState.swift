import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var codex = ProviderSnapshot.loading(.codex)
    @Published var claude = ProviderSnapshot.loading(.claude)
    @Published var history: [UsagePoint] = []
    @Published var quotaHistory: [QuotaHistoryPoint] = []
    @Published var analytics: [ProviderKind: UsageAnalyticsSnapshot] = [:]
    @Published var pace: [ProviderKind: PaceInsight] = [:]
    @Published var serviceHealth: [ProviderKind: ServiceHealthSnapshot] = [:]
    @Published var codexAccountDetails = CodexAccountDetails.empty
    @Published var claudeAccountDetails = ClaudeAccountDetails.empty
    @Published var showsRefreshIndicator = false
    @Published var lastUpdated: Date?
    @Published var taskText = ""
    @Published var recommendation: RouteRecommendation?
    @Published var routeMode: RouterAnalysisMode = .ai {
        didSet {
            guard routeMode != oldValue else { return }
            routeRequestTask?.cancel()
            routeRequestTask = nil
            isRoutingTask = false
            recommendation = nil
        }
    }
    @Published var isRoutingTask = false
    @Published var notificationPermissionMessage = ""
    @Published var claudePairingCode: String?
    @Published var claudeConnectorPaired = ClaudeBrowserBridge.shared.isPaired

    let settings = SettingsStore.shared
    private let coordinator = ProviderCoordinator()
    private let historyStore = UsageHistoryStore()
    private let quotaHistoryStore = QuotaHistoryStore()
    private let router = TaskRouter()
    private let routeAdvisor = CodexTaskRouteAdvisor()
    private let paceEngine = PaceEngine()
    private let costProvider = CostAnalyticsProvider()
    private let statusProvider = StatusProvider()
    private var refreshLoop: Task<Void, Never>?
    private var isRefreshing = false
    private var hasStarted = false
    private var lastAnalyticsRefresh: Date?
    private var analyticsBase: [ProviderKind: UsageAnalyticsSnapshot] = [:]
    private var lastStatusRefresh: Date?
    private var routeRequestTask: Task<Void, Never>?

    private init() {}

    var connectedSnapshots: [ProviderSnapshot] {
        [codex, claude].filter { $0.state == .connected }
    }

    var combinedRemaining: Double? {
        let values = connectedSnapshots.compactMap(\.remainingPercent)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var limitingProvider: ProviderSnapshot? {
        connectedSnapshots.min { ($0.remainingPercent ?? 101) < ($1.remainingPercent ?? 101) }
    }

    var nearestReset: Date? {
        connectedSnapshots.compactMap { $0.quota?.resetsAt }.min()
    }

    var healthLevel: HealthLevel {
        let levels = pace.values.map(\.level)
        if levels.contains(.critical) { return .critical }
        if levels.contains(.watch) { return .watch }
        if levels.contains(.healthy) { return .healthy }
        guard let remaining = combinedRemaining else { return .unknown }
        if remaining >= 35 { return .healthy }
        if remaining >= 15 { return .watch }
        return .critical
    }

    var codexAnalytics: UsageAnalyticsSnapshot { analytics[.codex] ?? .empty(.codex) }
    var claudeAnalytics: UsageAnalyticsSnapshot { analytics[.claude] ?? .empty(.claude) }

    var todayTokens: Int64 {
        analytics.values.compactMap { $0.daily.last }.filter { $0.parsedDate.map(Calendar.current.isDateInToday) == true }.reduce(0) { $0 + $1.totalTokens }
    }

    var todayCost: Double? {
        let values = analytics.values.compactMap { snapshot in
            snapshot.daily.last.flatMap { day in
                day.parsedDate.map(Calendar.current.isDateInToday) == true ? day.totalCost : nil
            }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    var allReceipts: [TaskReceipt] {
        analytics.values.flatMap(\.recentReceipts).sorted { $0.date > $1.date }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        ClaudeBrowserBridge.shared.start { [weak self] data in
            Task { @MainActor in
                self?.applyClaudeConnectorData(data)
            }
        }
        if settings.claudeUsageSource == .browserExtension,
           !ClaudeBrowserBridge.shared.isPaired {
            claudePairingCode = ClaudeBrowserBridge.shared.beginPairing()
        }
        Task {
            history = await historyStore.load()
            quotaHistory = await quotaHistoryStore.load()
            syncFloatingPanel()
            await refresh(forceAnalytics: true)
        }
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let seconds = UInt64(max(1, self.settings.refreshMinutes) * 60)
                try? await Task.sleep(for: .seconds(seconds))
                if !Task.isCancelled { await self.refresh() }
            }
        }
    }

    func refresh(forceAnalytics: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let shouldShowIndicator = forceAnalytics || lastUpdated == nil
        if shouldShowIndicator { showsRefreshIndicator = true }

        let analyticsIsDue = forceAnalytics
            || lastAnalyticsRefresh.map { Date.now.timeIntervalSince($0) > 600 } != false
        let statusIsDue = forceAnalytics
            || lastStatusRefresh.map { Date.now.timeIntervalSince($0) > 600 } != false
        let cachedAnalytics = analyticsBase
        let cachedHealth = serviceHealth
        let analyticsEnabled = settings.analyticsEnabled
        let statusEnabled = settings.statusChecksEnabled
        let statusProviders: Set<ProviderKind> = claude.state == .connected ? [.codex, .claude] : [.codex]

        async let codexResult = coordinator.fetchCodexData()
        async let claudeResult = coordinator.fetchClaudeData(
            source: settings.claudeUsageSource,
            allowBrowserCookieImport: settings.claudeBrowserCookieImportAllowed
        )
        async let costResult: [ProviderKind: UsageAnalyticsSnapshot] = analyticsEnabled && analyticsIsDue
            ? costProvider.fetch(days: UsagePeriod.quarter.rawValue)
            : (analyticsEnabled ? cachedAnalytics : [:])
        async let statusResult: [ProviderKind: ServiceHealthSnapshot] = statusEnabled && statusIsDue
            ? statusProvider.fetch(providers: statusProviders)
            : (statusEnabled ? cachedHealth : [:])

        let (codexData, claudeData, costData, healthData) = await (codexResult, claudeResult, costResult, statusResult)
        codex = codexData.snapshot
        claude = claudeData.snapshot
        claudeAccountDetails = claudeData.accountDetails
        codexAccountDetails = codexData.accountDetails
        let canReuseCachedAnalytics = analyticsEnabled && costData.isEmpty && !cachedAnalytics.isEmpty
        let resolvedCostData = canReuseCachedAnalytics ? cachedAnalytics : costData
        analyticsBase = analyticsEnabled ? merge(costData: resolvedCostData, codexData: codexData) : [:]
        selectUsagePeriod(settings.usagePeriod)
        serviceHealth = healthData
        if analyticsEnabled && analyticsIsDue && !costData.isEmpty {
            lastAnalyticsRefresh = .now
        }
        if statusEnabled && statusIsDue {
            lastStatusRefresh = .now
        }
        history = await historyStore.record([codex, claude])
        quotaHistory = await quotaHistoryStore.record(quotaHistorySamples())
        pace[.codex] = paceEngine.insight(for: codex, history: history)
        pace[.claude] = paceEngine.insight(for: claude, history: history)
        lastUpdated = .now
        isRefreshing = false
        if shouldShowIndicator { showsRefreshIndicator = false }

        if codex.state == .connected {
            await NotificationService.shared.evaluate(provider: codex, insight: pace[.codex] ?? .unknown, settings: settings)
        }
        if claude.state == .connected {
            await NotificationService.shared.evaluate(provider: claude, insight: pace[.claude] ?? .unknown, settings: settings)
        }
    }

    func selectUsagePeriod(_ period: UsagePeriod) {
        analytics = analyticsBase.mapValues { $0.filtered(to: period) }
    }

    func refreshClaudeConnection() async {
        let requestedSource = settings.claudeUsageSource
        claude = .loading(.claude)
        let data = await coordinator.fetchClaudeData(
            source: requestedSource,
            allowBrowserCookieImport: settings.claudeBrowserCookieImportAllowed
        )
        guard settings.claudeUsageSource == requestedSource else { return }
        claude = data.snapshot
        claudeAccountDetails = data.accountDetails
        history = await historyStore.record([codex, claude])
        quotaHistory = await quotaHistoryStore.record(quotaHistorySamples())
        pace[.claude] = paceEngine.insight(for: claude, history: history)
        lastUpdated = .now
        if claude.state == .connected {
            await NotificationService.shared.evaluate(
                provider: claude,
                insight: pace[.claude] ?? .unknown,
                settings: settings
            )
        }
    }

    func beginClaudeConnectorPairing() {
        settings.claudeBrowserCookieImportAllowed = false
        settings.claudeUsageSource = .browserExtension
        claudePairingCode = ClaudeBrowserBridge.shared.beginPairing()
        claudeConnectorPaired = ClaudeBrowserBridge.shared.isPaired
        if !claudeConnectorPaired {
            claude = .unavailable(
                .claude,
                message: "Install Pulse Connector in the Chrome profile where Claude is signed in, then enter the pairing code"
            )
        }
    }

    func revokeClaudeConnector() {
        ClaudeBrowserBridge.shared.revoke()
        claudePairingCode = nil
        claudeConnectorPaired = false
        settings.claudeUsageSource = .off
        claude = .unavailable(.claude, message: "Claude Web is not connected")
        claudeAccountDetails = .empty
    }

    func refreshClaudeConnectorState() {
        claudeConnectorPaired = ClaudeBrowserBridge.shared.isPaired
        if claudeConnectorPaired, let data = ClaudeBrowserBridge.shared.latestData {
            applyClaudeConnectorData(data)
        }
    }

    func routeCurrentTask() {
        let trimmed = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
        routeRequestTask?.cancel()
        routeRequestTask = nil
        guard !trimmed.isEmpty else {
            recommendation = nil
            isRoutingTask = false
            return
        }

        if routeMode == .local {
            isRoutingTask = false
            recommendation = router.recommend(
                task: trimmed,
                codex: codex,
                claude: claude,
                analytics: analytics,
                source: .localRules
            )
            return
        }

        guard codex.state == .connected else {
            isRoutingTask = false
            recommendation = router.recommend(
                task: trimmed,
                codex: codex,
                claude: claude,
                analytics: analytics,
                source: .localFallback
            )
            return
        }

        isRoutingTask = true
        recommendation = router.recommend(
            task: trimmed,
            codex: codex,
            claude: claude,
            analytics: analytics,
            source: .localRules
        )
        routeRequestTask = Task { [weak self] in
            guard let self else { return }
            do {
                let assessment = try await routeAdvisor.analyze(task: trimmed)
                guard !Task.isCancelled,
                      routeMode == .ai,
                      taskText.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
                else { return }
                recommendation = router.recommend(
                    task: trimmed,
                    assessment: assessment,
                    codex: codex,
                    claude: claude,
                    analytics: analytics
                )
            } catch {
                guard !Task.isCancelled,
                      routeMode == .ai,
                      taskText.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
                else { return }
                recommendation = router.recommend(
                    task: trimmed,
                    codex: codex,
                    claude: claude,
                    analytics: analytics,
                    source: .localFallback
                )
            }
            isRoutingTask = false
            routeRequestTask = nil
        }
    }

    func requestNotificationPermission() async -> Bool {
        await NotificationService.shared.requestPermission()
    }

    func syncFloatingPanel() {
        if settings.showFloatingWidget {
            FloatingPanelController.shared.show()
            FloatingPanelController.shared.applySettings(settings)
        } else {
            FloatingPanelController.shared.hide()
        }
    }

    private func applyClaudeConnectorData(_ data: ClaudeProviderData) {
        guard settings.claudeUsageSource == .browserExtension else { return }
        claude = data.snapshot
        claudeAccountDetails = data.accountDetails
        claudeConnectorPaired = true
        claudePairingCode = nil
        lastUpdated = .now
        Task {
            history = await historyStore.record([codex, claude])
            quotaHistory = await quotaHistoryStore.record(quotaHistorySamples())
            pace[.claude] = paceEngine.insight(for: claude, history: history)
        }
    }

    private func quotaHistorySamples() -> [QuotaHistorySample] {
        var samples: [QuotaHistorySample] = []

        for bucket in codexAccountDetails.quotaBuckets {
            let title = bucket.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let primary = bucket.primary {
                samples.append(QuotaHistorySample(
                    provider: .codex,
                    windowID: "\(bucket.id)-primary",
                    scope: historyScope(for: primary),
                    title: title?.isEmpty == false ? title : "Codex",
                    usedPercent: primary.usedPercent,
                    resetsAt: primary.resetsAt,
                    windowMinutes: primary.windowMinutes
                ))
            }
            if let secondary = bucket.secondary {
                samples.append(QuotaHistorySample(
                    provider: .codex,
                    windowID: "\(bucket.id)-secondary",
                    scope: historyScope(for: secondary),
                    title: title?.isEmpty == false ? title : "Codex",
                    usedPercent: secondary.usedPercent,
                    resetsAt: secondary.resetsAt,
                    windowMinutes: secondary.windowMinutes
                ))
            }
        }
        if !samples.contains(where: { $0.provider == .codex }),
           codex.state == .connected,
           let window = codex.quota {
            samples.append(QuotaHistorySample(
                provider: .codex,
                windowID: "codex-limiting",
                scope: historyScope(for: window),
                title: "Codex",
                usedPercent: window.usedPercent,
                resetsAt: window.resetsAt,
                windowMinutes: window.windowMinutes
            ))
        }

        samples.append(contentsOf: claudeAccountDetails.quotaMeters.filter(\.usageKnown).map { meter in
            let scope: QuotaHistoryScope = switch meter.scope {
            case .session: .session
            case .weekly: .weekly
            case .modelWeekly: .modelWeekly
            }
            return QuotaHistorySample(
                provider: .claude,
                windowID: meter.id,
                scope: scope,
                title: meter.providerTitle,
                usedPercent: meter.window.usedPercent,
                resetsAt: meter.window.resetsAt,
                windowMinutes: meter.window.windowMinutes
            )
        })
        if !samples.contains(where: { $0.provider == .claude }),
           claude.state == .connected,
           let window = claude.quota {
            samples.append(QuotaHistorySample(
                provider: .claude,
                windowID: "claude-limiting",
                scope: historyScope(for: window),
                title: nil,
                usedPercent: window.usedPercent,
                resetsAt: window.resetsAt,
                windowMinutes: window.windowMinutes
            ))
        }
        return samples
    }

    private func historyScope(for window: QuotaWindow) -> QuotaHistoryScope {
        switch window.windowMinutes {
        case 300: .session
        case 10_080: .weekly
        default: .other
        }
    }

    private func merge(
        costData: [ProviderKind: UsageAnalyticsSnapshot],
        codexData: CodexProviderData
    ) -> [ProviderKind: UsageAnalyticsSnapshot] {
        var result = costData
        let base = result[.codex] ?? .empty(.codex)
        result[.codex] = UsageAnalyticsSnapshot(
            provider: .codex,
            currencyCode: base.currencyCode,
            source: base.source.isEmpty ? "Codex App Server" : base.source,
            updatedAt: max(base.updatedAt, codexData.snapshot.updatedAt),
            totals: base.totals,
            daily: base.daily,
            projects: base.projects,
            accountSummary: codexData.accountSummary,
            accountDaily: codexData.accountDaily
        )
        return result
    }
}

enum HealthLevel: Int, Hashable, Sendable {
    case healthy
    case watch
    case critical
    case unknown

    var color: Color {
        switch self {
        case .healthy: .pulseGreen
        case .watch: .yellow
        case .critical: .red
        case .unknown: .secondary
        }
    }
}
