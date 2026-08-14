import Charts
import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview
    case usage
    case receipts
    case router
    case settings
    var id: String { rawValue }
}

enum UsageDataMode: String, CaseIterable, Identifiable {
    case quotas
    case tokens
    var id: String { rawValue }
}

enum ProviderFilter: String, CaseIterable, Identifiable {
    case all
    case codex
    case claude
    var id: String { rawValue }

    func includes(_ provider: ProviderKind) -> Bool {
        self == .all || rawValue == provider.rawValue
    }
}

enum UsageHistoryMode: String, CaseIterable, Identifiable {
    case tokenReceipts
    case quotaEvents
    var id: String { rawValue }
}

@MainActor
final class DashboardUIState: ObservableObject {
    static let shared = DashboardUIState()
    @Published var section: DashboardSection = .overview
    @Published var showQuickSettings = false
    @Published var usageDataMode: UsageDataMode = .quotas
    @Published var usageProviderFilter: ProviderFilter = .all
    @Published var usageTab: UsageTab = .timeline
    @Published var projectSearch = ""
    @Published var selectedUsageDayID: String?
    @Published var receiptCategory: TaskCategory?
    @Published var receiptDate: Date?
    @Published var usageHistoryMode: UsageHistoryMode = .tokenReceipts
    @Published var historyProviderFilter: ProviderFilter = .all
}

struct DashboardView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var ui = DashboardUIState.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.45)
            Group {
                switch ui.section {
                case .overview: OverviewScreen()
                case .usage: UsageIntelligenceScreen()
                case .receipts: ReceiptsScreen()
                case .router: RouterScreen()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar { toolbar }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.pulseTeal)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Codex Pulse").font(.headline)
                    Text("\(appVersion) · \(L10n.experienceTitle(settings.experienceMode, language: settings.language))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 16)

            sideButton(.overview, icon: "rectangle.grid.2x2", ru: "Обзор", en: "Overview")
            sideButton(.usage, icon: "chart.bar.xaxis", ru: "Использование", en: "Usage")
            sideButton(.receipts, icon: "clock.arrow.circlepath", ru: "История расхода", en: "Usage history")
            sideButton(.router, icon: "point.3.connected.trianglepath.dotted", ru: "Маршрут задачи", en: "Task router")
            sideButton(.settings, icon: "gearshape", ru: "Настройки", en: "Settings")

            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Label(tr(settings.language, "Локально и приватно", "Local and private"), systemImage: "lock.shield")
                    .font(.caption.weight(.semibold))
                Text(tr(
                    settings.language,
                    "История квот обоих сервисов и токен-агрегаты доступных источников — без текстов промптов.",
                    "Quota history for both services and token aggregates from available sources — without prompt text."
                ))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .pulseSurface()
        }
        .padding(18)
        .frame(width: 220)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private func sideButton(_ item: DashboardSection, icon: String, ru: String, en: String) -> some View {
        Button {
            ui.section = item
        } label: {
            Label(tr(settings.language, ru, en), systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 9)
                .padding(.horizontal, 10)
                .background(ui.section == item ? Color.pulseTeal.opacity(0.13) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if state.showsRefreshIndicator { ProgressView().controlSize(.small) }
            Button { Task { await state.refresh(forceAnalytics: true) } } label: { Image(systemName: "arrow.clockwise") }
                .help(tr(settings.language, "Обновить", "Refresh"))
            Button { ui.showQuickSettings.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                .popover(isPresented: $ui.showQuickSettings, arrowEdge: .top) {
                    QuickSettingsView().environmentObject(state).environmentObject(settings).frame(width: 360).padding(18)
                }
        }
    }
}

private struct OverviewScreen: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                HStack(spacing: 14) {
                    ProviderCard(snapshot: state.codex)
                    if state.claude.state == .connected || settings.showUnavailableProviders {
                        ProviderCard(snapshot: state.claude)
                    }
                    BudgetCard().frame(minWidth: 230)
                }
                if !codexQuotaMeters(state.codexAccountDetails, language: settings.language).isEmpty {
                    CodexQuotaDetailsCard()
                }
                if state.claude.state == .connected,
                   !claudeQuotaMeters(state.claudeAccountDetails, language: settings.language).isEmpty {
                    ClaudeQuotaDetailsCard()
                }
                UsageSummaryCard()
                TaskRouterCard()
            }
            .padding(22)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tr(settings.language, "AI-бюджет под контролем", "Your AI budget, under control"))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(tr(settings.language, "Остаток, темп, расходы и лучший маршрут следующей задачи", "Quota, pace, cost, and the best route for your next task"))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let updated = state.lastUpdated {
                Text(tr(settings.language, "Обновлено ", "Updated ") + localizedDate(updated, language: settings.language, dateStyle: .none, timeStyle: .short))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProviderCard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore
    let snapshot: ProviderSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label(snapshot.provider.displayName, systemImage: snapshot.provider.symbol)
                    .font(.title3.weight(.semibold)).foregroundStyle(snapshot.provider.tint)
                Spacer()
                statusPill
            }

            if let remaining = snapshot.remainingPercent {
                HStack(spacing: 15) {
                    quotaRing(remaining)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(quotaResetText(snapshot.quota?.resetsAt, language: settings.language))
                            .font(.headline.monospacedDigit())
                        Label(
                            quotaForecastText(state.pace[snapshot.provider], language: settings.language),
                            systemImage: state.pace[snapshot.provider]?.level == .healthy
                                ? "checkmark.circle.fill"
                                : "clock.badge.exclamationmark"
                        )
                        .font(.caption)
                        .foregroundStyle(state.pace[snapshot.provider]?.level.color ?? .secondary)
                        if let safe = state.pace[snapshot.provider]?.safePercentToday {
                            Label(tr(settings.language, "сегодня не более \(Int(safe.rounded()))%", "no more than \(Int(safe.rounded()))% today"), systemImage: "speedometer")
                                .font(.caption).foregroundStyle(state.pace[snapshot.provider]?.level.color ?? .secondary)
                        }
                        Text(snapshot.source).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr(settings.language, "Не подключён", "Not connected")).font(.title3.weight(.medium))
                    Text(snapshot.provider == .claude
                         ? tr(settings.language, "Подключите Claude Web в настройках. Pulse не запрашивает пароль.", "Connect Claude Web in Settings. Pulse never asks for your password.")
                         : snapshot.message ?? tr(settings.language, "Нет данных", "No data"))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .pulseSurface()
    }

    private func quotaRing(_ value: Double) -> some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.16), lineWidth: 9)
            Circle().trim(from: 0, to: value / 100)
                .stroke(snapshot.provider.tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(percentText(value)).font(.system(size: 25, weight: .medium, design: .monospaced))
                Text(tr(settings.language, "осталось", "left")).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 104, height: 104)
        .accessibilityLabel("\(snapshot.provider.displayName), \(percentText(value))")
    }

    private var statusPill: some View {
        return HStack(spacing: 5) {
            Circle().fill(connectionColor).frame(width: 7, height: 7)
            Text(statusTitle).font(.caption)
        }
        .foregroundStyle(.secondary)
    }

    private var statusTitle: String {
        switch snapshot.state {
        case .connected: tr(settings.language, "Активно", "Active")
        case .loading: tr(settings.language, "Загрузка", "Loading")
        case .unavailable: tr(settings.language, "Нет связи", "Offline")
        case .error: tr(settings.language, "Ошибка", "Error")
        }
    }

    private var connectionColor: Color {
        switch snapshot.state {
        case .connected: return .pulseGreen
        case .loading: return .yellow
        case .unavailable: return .secondary
        case .error: return .red
        }
    }
}

private struct CodexQuotaDetailsCard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(tr(settings.language, "Окна Codex", "Codex quota windows"), systemImage: "gauge.with.dots.needle.67percent")
                    .font(.headline)
                if let plan = codexPlanName(state.codexAccountDetails.planType, language: settings.language) {
                    Text(plan).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let balance = state.codexAccountDetails.creditBalance, balance != "0" {
                    Label(balance, systemImage: "creditcard").font(.caption.monospacedDigit())
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                ForEach(codexQuotaMeters(state.codexAccountDetails, language: settings.language)) { meter in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(meter.title).font(.callout.weight(.semibold)).lineLimit(1)
                            Spacer()
                            Text(percentText(meter.window.remainingPercent)).font(.headline.monospacedDigit())
                        }
                        ProgressView(value: meter.window.remainingPercent, total: 100)
                            .tint(Color.pulseTeal)
                            .accessibilityLabel(tr(
                                settings.language,
                                "Осталось \(percentText(meter.window.remainingPercent)). \(quotaResetText(meter.window.resetsAt, language: settings.language))",
                                "\(percentText(meter.window.remainingPercent)) left. \(quotaResetText(meter.window.resetsAt, language: settings.language))"
                            ))
                        Text(quotaResetText(meter.window.resetsAt, language: settings.language))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
            }
        }
        .padding(16)
        .pulseSurface()
    }
}

private struct ClaudeQuotaDetailsCard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(tr(settings.language, "Лимиты Claude", "Claude quota windows"), systemImage: ProviderKind.claude.symbol)
                    .font(.headline)
                    .foregroundStyle(ProviderKind.claude.tint)
                if let plan = state.claudeAccountDetails.planName {
                    Text(plan).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let balance = state.claudeAccountDetails.creditBalance {
                    Label(balance, systemImage: "creditcard").font(.caption.monospacedDigit())
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                ForEach(claudeQuotaMeters(state.claudeAccountDetails, language: settings.language)) { meter in
                    ClaudeQuotaMeterView(meter: meter, language: settings.language)
                    .padding(12)
                    .background(Color.primary.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
            }
            Text(tr(
                settings.language,
                "Pulse показывает только те окна, которые Claude Web вернул прямо сейчас. Данные из Chrome обновляются автоматически.",
                "Pulse shows only the windows returned by Claude Web right now. Chrome data refreshes automatically."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .pulseSurface()
    }
}

private struct BudgetCard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(tr(settings.language, "Умный темп", "Smart pace"), systemImage: "gauge.with.dots.needle.50percent")
                .font(.headline)
            Text(title).font(.title2.weight(.semibold)).foregroundStyle(state.healthLevel.color)
            Text(explanation).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let provider = state.limitingProvider,
               let insight = state.pace[provider.provider] {
                Label(
                    quotaForecastText(insight, language: settings.language),
                    systemImage: insight.level == .healthy ? "checkmark.circle.fill" : "calendar.badge.exclamationmark"
                )
                .font(.callout.weight(.semibold))
                .foregroundStyle(state.healthLevel.color)
                if let safe = insight.safePercentToday {
                    Text("\(Int(safe.rounded()))%")
                        .font(.system(size: 30, weight: .medium, design: .monospaced))
                    Text(tr(settings.language, "можно безопасно потратить сегодня", "safe to use today"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .pulseSurface()
    }

    private var title: String {
        switch state.healthLevel {
        case .healthy: tr(settings.language, "Всё спокойно", "All good")
        case .watch: tr(settings.language, "Темп высоковат", "Pace is high")
        case .critical: tr(settings.language, "Пора экономить", "Time to conserve")
        case .unknown: tr(settings.language, "Изучаем темп", "Learning your pace")
        }
    }

    private var explanation: String {
        switch state.healthLevel {
        case .healthy: tr(settings.language, "Можно продолжать и выбирать модель по сложности задачи.", "Keep working and choose models by task complexity.")
        case .watch: tr(settings.language, "Для большой задачи сначала проверьте маршрут и прогноз.", "Check the route and forecast before a large task.")
        case .critical: tr(settings.language, "Разбейте большую задачу или дождитесь сброса.", "Split a large task or wait for reset.")
        case .unknown: tr(settings.language, "Нужно несколько обновлений, чтобы рассчитать скорость расхода.", "A few refreshes are needed to calculate burn rate.")
        }
    }
}

private struct UsageSummaryCard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(tokenSummaryTitle).font(.headline)
                Spacer()
                Text(tr(settings.language, "Локальная оценка · \(settings.usagePeriod.rawValue) дней", "Local estimate · \(settings.usagePeriod.rawValue) days"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if state.analytics.values.allSatisfy({ $0.daily.isEmpty }) {
                emptyAnalytics
            } else {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        metric(tr(settings.language, "Сегодня", "Today"), compactTokens(state.todayTokens), cost: state.todayCost)
                        metric(tr(settings.language, "За период", "Period"), compactTokens(totalTokens), cost: totalCost)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        smallRanking(title: tr(settings.language, "Топ-модель", "Top model"), value: topModel)
                        smallRanking(title: tr(settings.language, "Топ-проект", "Top project"), value: topProject)
                    }
                    Spacer()
                    MiniUsageChart(days: mergedDaily).frame(width: 330, height: 110)
                }
            }
        }
        .padding(16)
        .pulseSurface()
    }

    private var emptyAnalytics: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis").font(.title2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(tr(settings.language, "Собираем локальную историю", "Building local history")).font(.headline)
                Text(tr(settings.language, "Данные появятся после первого успешного сканирования агрегатов.", "Data appears after the first successful aggregate scan."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
    }

    private func metric(_ title: String, _ value: String, cost: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
            if settings.showEstimatedCost, let cost { Text(currency(cost, language: settings.language)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
        }
    }

    private func smallRanking(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold)).lineLimit(1)
        }
    }

    private var totalTokens: Int64 { state.analytics.values.reduce(0) { $0 + $1.totals.totalTokens } }
    private var tokenSummaryTitle: String {
        let providers = state.analytics.values
            .filter { !$0.daily.isEmpty || $0.totals.totalTokens > 0 }
            .map(\.provider.displayName)
            .sorted()
            .joined(separator: " + ")
        let suffix = providers.isEmpty ? "" : " · \(providers)"
        return tr(settings.language, "Куда ушли токены\(suffix)", "Where your tokens went\(suffix)")
    }
    private var totalCost: Double? {
        let values = state.analytics.values.compactMap(\.totals.totalCost)
        return values.isEmpty ? nil : values.reduce(0, +)
    }
    private var topModel: String {
        state.analytics.values.flatMap(\.modelTotals).max(by: { $0.totalTokens < $1.totalTokens })?.modelName ?? "—"
    }
    private var topProject: String {
        state.analytics.values.flatMap(\.projects).max(by: { $0.totalTokens < $1.totalTokens })?.name ?? "—"
    }
    private var mergedDaily: [DailyTokenUsage] { state.analytics.values.flatMap(\.daily).sorted { $0.date < $1.date } }
}

private struct MiniUsageChart: View {
    let days: [DailyTokenUsage]
    var body: some View {
        Chart(days) { day in
            BarMark(x: .value("Date", day.parsedDate ?? .now), y: .value("Tokens", day.totalTokens))
                .foregroundStyle(Color.pulseTeal.gradient)
                .cornerRadius(3)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityLabel("Daily token usage chart")
    }
}

enum UsageTab: String, CaseIterable, Identifiable {
    case timeline
    case models
    case projects
    case calendar
    var id: String { rawValue }
}

private struct UsageIntelligenceScreen: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var ui = DashboardUIState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr(settings.language, "Использование", "Usage intelligence")).font(.largeTitle.weight(.semibold))
                    Text(usageSubtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $settings.usagePeriod) {
                    Text("7d").tag(UsagePeriod.week)
                    Text("30d").tag(UsagePeriod.month)
                    Text("90d").tag(UsagePeriod.quarter)
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 190)
                .onChange(of: settings.usagePeriod) { period in state.selectUsagePeriod(period) }
            }

            HStack(spacing: 12) {
                Picker("", selection: $ui.usageDataMode) {
                    Text(tr(settings.language, "Лимиты и темп", "Quota and pace")).tag(UsageDataMode.quotas)
                    Text(tr(settings.language, "Токены и стоимость", "Tokens and cost")).tag(UsageDataMode.tokens)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 520)

                Spacer()
                ProviderFilterPicker(selection: $ui.usageProviderFilter)
            }

            Group {
                if ui.usageDataMode == .quotas {
                    QuotaAnalyticsView()
                } else if tokenAnalytics.isEmpty {
                    EmptyDataCard(
                        icon: "chart.bar.xaxis",
                        title: tr(settings.language, "Claude Web не передаёт токены", "Claude Web does not provide token totals"),
                        message: tr(
                            settings.language,
                            "Для Claude доступны точные проценты лимита, сбросы и прогноз темпа. Переключитесь на «Лимиты и темп» — Pulse не будет придумывать токены, проекты или стоимость.",
                            "Claude provides exact quota percentages, resets, and pace forecasts. Switch to Quota and pace — Pulse will not invent tokens, projects, or cost."
                        ),
                        actionTitle: tr(settings.language, "Показать лимиты Claude", "Show Claude quotas")
                    ) {
                        ui.usageDataMode = .quotas
                    }
                } else {
                    VStack(spacing: 14) {
                        Picker("", selection: $ui.usageTab) {
                            Text(tr(settings.language, "Динамика", "Timeline")).tag(UsageTab.timeline)
                            Text(tr(settings.language, "Модели", "Models")).tag(UsageTab.models)
                            Text(tr(settings.language, "Проекты", "Projects")).tag(UsageTab.projects)
                            Text(tr(settings.language, "По дням", "By day")).tag(UsageTab.calendar)
                        }
                        .labelsHidden().pickerStyle(.segmented)

                        Group {
                            switch ui.usageTab {
                            case .timeline: TimelineUsageView()
                            case .models: ModelUsageView()
                            case .projects: ProjectUsageView()
                            case .calendar: UsageHeatmapView()
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
    }

    private var usageSubtitle: String {
        ui.usageDataMode == .quotas
            ? tr(settings.language, "История процентов, сбросов и темпа Codex и Claude", "Percentage, reset, and pace history for Codex and Claude")
            : tr(settings.language, "Токены, модели, проекты и оценочная стоимость из доступных локальных источников", "Tokens, models, projects, and estimated cost from available local sources")
    }

    private var tokenAnalytics: [UsageAnalyticsSnapshot] {
        state.analytics.values.filter {
            ui.usageProviderFilter.includes($0.provider) && (!$0.daily.isEmpty || $0.totals.totalTokens > 0)
        }
    }
}

private struct ProviderFilterPicker: View {
    @EnvironmentObject private var settings: SettingsStore
    @Binding var selection: ProviderFilter

    var body: some View {
        Picker("", selection: $selection) {
            Text(tr(settings.language, "Все", "All")).tag(ProviderFilter.all)
            Text("Codex").tag(ProviderFilter.codex)
            Text("Claude").tag(ProviderFilter.claude)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 250)
    }
}

private struct QuotaAnalyticsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var ui = DashboardUIState.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if currentItems.isEmpty && historyPoints.isEmpty {
                    EmptyDataCard(
                        icon: "gauge.with.dots.needle.33percent",
                        title: tr(settings.language, "История лимитов пока пуста", "Quota history is empty"),
                        message: tr(
                            settings.language,
                            "Подключите сервис или обновите данные. Pulse начнёт локально сохранять проценты каждого окна — без текстов чатов.",
                            "Connect a provider or refresh. Pulse will start storing each window's percentages locally — without chat text."
                        ),
                        actionTitle: tr(settings.language, "Обновить данные", "Refresh data")
                    ) {
                        Task { await state.refresh(forceAnalytics: true) }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                        ForEach(currentItems) { item in currentQuotaCard(item) }
                    }

                    quotaTrend
                    paceSummary
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func currentQuotaCard(_ item: CurrentQuotaItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: item.provider.symbol).foregroundStyle(item.provider.tint)
                Text(item.title).font(.headline).lineLimit(2)
                Spacer(minLength: 8)
                Text(percentText(item.window.remainingPercent))
                    .font(.title2.monospacedDigit().weight(.semibold))
            }
            ProgressView(value: item.window.remainingPercent, total: 100)
                .tint(item.provider.tint)
                .accessibilityLabel(tr(
                    settings.language,
                    "Осталось \(percentText(item.window.remainingPercent))",
                    "\(percentText(item.window.remainingPercent)) remaining"
                ))
            HStack(alignment: .firstTextBaseline) {
                Text(quotaUsageText(item.window, language: settings.language))
                Spacer()
                Text(quotaResetText(item.window.resetsAt, language: settings.language, compact: true))
                    .multilineTextAlignment(.trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulseSurface()
    }

    private var quotaTrend: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr(settings.language, "Динамика лимитов", "Quota trend")).font(.headline)
                    Text(tr(settings.language, "Процент использованного лимита · \(settings.usagePeriod.rawValue) дней", "Percent of quota used · \(settings.usagePeriod.rawValue) days"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(tr(settings.language, "0% свободно · 100% исчерпано", "0% unused · 100% exhausted"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            if historyPoints.isEmpty {
                Text(tr(
                    settings.language,
                    "Первый снимок появится после обновления подключённого сервиса.",
                    "The first snapshot appears after the connected provider refreshes."
                ))
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
            } else {
                Chart(historyPoints) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Used", point.usedPercent),
                        series: .value("Window", seriesTitle(point))
                    )
                    .foregroundStyle(point.provider.tint)
                    .interpolationMethod(.monotone)
                    PointMark(
                        x: .value("Time", point.date),
                        y: .value("Used", point.usedPercent)
                    )
                    .foregroundStyle(point.provider.tint)
                    .symbolSize(28)
                }
                .chartYScale(domain: 0 ... 100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.16))
                        AxisValueLabel {
                            if let percent = value.as(Int.self) { Text("\(percent)%") }
                        }
                    }
                }
                .frame(minHeight: 300)
                .accessibilityLabel(tr(settings.language, "График использования лимитов", "Quota utilization chart"))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 8)], spacing: 8) {
                    ForEach(latestHistoryPoints) { point in
                        HStack(spacing: 8) {
                            Image(systemName: point.provider.symbol).foregroundStyle(point.provider.tint)
                            Text(historyTitle(point)).lineLimit(1)
                            Spacer()
                            Text(percentText(point.usedPercent))
                                .font(.callout.monospacedDigit().weight(.semibold))
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .padding(16)
        .pulseSurface()
    }

    private var paceSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr(settings.language, "Темп по сервисам", "Provider pace")).font(.headline)
            ForEach(paceProviders, id: \.provider) { snapshot in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill((state.pace[snapshot.provider]?.level ?? .unknown).color).frame(width: 9, height: 9).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.provider.displayName).font(.callout.weight(.semibold))
                        Text(quotaForecastText(state.pace[snapshot.provider], language: settings.language))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let safe = state.pace[snapshot.provider]?.safePercentToday {
                        Text(tr(settings.language, "сегодня до \(percentText(safe))", "up to \(percentText(safe)) today"))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .pulseSurface()
    }

    private struct CurrentQuotaItem: Identifiable {
        let provider: ProviderKind
        let id: String
        let title: String
        let window: QuotaWindow
    }

    private var currentItems: [CurrentQuotaItem] {
        var result: [CurrentQuotaItem] = []
        if ui.usageProviderFilter.includes(.codex) {
            result += codexQuotaMeters(state.codexAccountDetails, language: settings.language).map {
                CurrentQuotaItem(provider: .codex, id: "codex-\($0.id)", title: $0.title, window: $0.window)
            }
        }
        if ui.usageProviderFilter.includes(.claude) {
            result += claudeQuotaMeters(state.claudeAccountDetails, language: settings.language, includeProvider: false).map {
                CurrentQuotaItem(provider: .claude, id: "claude-\($0.id)", title: $0.title, window: $0.window)
            }
        }
        return result
    }

    private var historyPoints: [QuotaHistoryPoint] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -settings.usagePeriod.rawValue, to: .now) ?? .distantPast
        return state.quotaHistory.filter {
            $0.date >= cutoff && ui.usageProviderFilter.includes($0.provider)
        }
    }

    private var latestHistoryPoints: [QuotaHistoryPoint] {
        Dictionary(grouping: historyPoints, by: { "\($0.provider.rawValue)-\($0.windowID)" })
            .compactMap { $0.value.max(by: { $0.date < $1.date }) }
            .sorted { historyTitle($0) < historyTitle($1) }
    }

    private var paceProviders: [ProviderSnapshot] {
        state.connectedSnapshots.filter { ui.usageProviderFilter.includes($0.provider) }
    }

    private func seriesTitle(_ point: QuotaHistoryPoint) -> String {
        point.provider.displayName + " · " + historyTitle(point)
    }

    private func historyTitle(_ point: QuotaHistoryPoint) -> String {
        if point.provider == .codex {
            let base = point.title?.isEmpty == false ? point.title! : "Codex"
            return base + " · " + quotaWindowName(point.windowMinutes, language: settings.language)
        }
        return switch point.scope {
        case .session: tr(settings.language, "Текущая сессия", "Current session")
        case .weekly: tr(settings.language, "Все модели · неделя", "All models · week")
        case .modelWeekly:
            (point.title ?? tr(settings.language, "Модель", "Model")) + tr(settings.language, " · неделя", " · week")
        case .other: point.title ?? "Claude"
        }
    }
}

@MainActor
private func filteredAnalytics(state: AppState, filter: ProviderFilter) -> [UsageAnalyticsSnapshot] {
    state.analytics.values.filter { filter.includes($0.provider) }
}

private struct TimelineUsageView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                summaryTile(tr(settings.language, "Токены", "Tokens"), compactTokens(totalTokens), "number")
                summaryTile(tr(settings.language, "Кэш", "Cache"), compactTokens(cacheTokens), "bolt.horizontal.circle")
                summaryTile(tr(settings.language, "Вывод", "Output"), compactTokens(outputTokens), "arrow.up.circle")
                summaryTile(tr(settings.language, "Оценка", "Estimate"), totalCost.map { currency($0, language: settings.language) } ?? "—", "dollarsign.circle")
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(tr(settings.language, "Расход по дням", "Daily usage")).font(.headline)
                Chart(rows) { row in
                    BarMark(x: .value("Date", row.date), y: .value("Tokens", row.tokens))
                        .foregroundStyle(row.provider.tint)
                        .cornerRadius(3)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.16))
                        AxisValueLabel {
                            if let tokens = value.as(Int64.self) { Text(compactTokens(tokens)) }
                        }
                    }
                }
                .frame(minHeight: 300)
                .accessibilityLabel(tr(settings.language, "График расхода токенов по дням", "Daily token usage chart"))
            }
            .padding(16).pulseSurface()
        }
    }

    private func summaryTile(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.monospacedDigit().weight(.semibold))
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).pulseSurface()
    }

    private struct Row: Identifiable { let provider: ProviderKind; let date: Date; let tokens: Int64; var id: String { provider.rawValue + date.description } }
    private var snapshots: [UsageAnalyticsSnapshot] { filteredAnalytics(state: state, filter: DashboardUIState.shared.usageProviderFilter) }
    private var rows: [Row] { snapshots.flatMap { snapshot in snapshot.daily.compactMap { day in day.parsedDate.map { Row(provider: snapshot.provider, date: $0, tokens: day.totalTokens) } } } }
    private var totalTokens: Int64 { snapshots.reduce(0) { $0 + $1.totals.totalTokens } }
    private var cacheTokens: Int64 { snapshots.reduce(0) { $0 + $1.totals.cacheReadTokens } }
    private var outputTokens: Int64 { snapshots.reduce(0) { $0 + $1.totals.outputTokens } }
    private var totalCost: Double? { let v = snapshots.compactMap(\.totals.totalCost); return v.isEmpty ? nil : v.reduce(0, +) }
}

private struct ModelUsageView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(models) { model in
                    HStack(spacing: 12) {
                        Image(systemName: modelIcon(model.modelName)).foregroundStyle(modelColor(model.modelName)).frame(width: 28)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(model.modelName).font(.headline); Spacer(); Text(compactTokens(model.totalTokens)).font(.headline.monospacedDigit()) }
                            ProgressView(value: Double(model.totalTokens), total: Double(maxTokens)).tint(modelColor(model.modelName))
                        }
                        if settings.showEstimatedCost, let cost = model.cost {
                            Text(currency(cost, language: settings.language)).font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                        }
                    }
                    .padding(14).pulseSurface()
                }
            }
        }
    }
    private var models: [ModelUsage] {
        var merged: [String: (Int64, Double, Bool)] = [:]
        for model in filteredAnalytics(state: state, filter: DashboardUIState.shared.usageProviderFilter).flatMap(\.modelTotals) {
            var item = merged[model.modelName] ?? (0, 0, false)
            item.0 += model.totalTokens
            if let cost = model.cost { item.1 += cost; item.2 = true }
            merged[model.modelName] = item
        }
        return merged.map { ModelUsage(modelName: $0.key, totalTokens: $0.value.0, cost: $0.value.2 ? $0.value.1 : nil) }.sorted { $0.totalTokens > $1.totalTokens }
    }
    private var maxTokens: Int64 { max(1, models.first?.totalTokens ?? 1) }
    private func modelColor(_ name: String) -> Color { name.lowercased().contains("sol") ? .pulseOrange : (name.lowercased().contains("terra") ? .pulseTeal : .pulseGreen) }
    private func modelIcon(_ name: String) -> String { name.lowercased().contains("sol") ? "sun.max.fill" : (name.lowercased().contains("terra") ? "globe.americas.fill" : "moon.stars.fill") }
}

private struct ProjectUsageView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var ui = DashboardUIState.shared
    var body: some View {
        VStack(spacing: 12) {
            TextField(tr(settings.language, "Поиск проектов", "Search projects"), text: $ui.projectSearch).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(projects) { project in
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill").foregroundStyle(Color.pulseTeal).frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(project.name).font(.headline).lineLimit(1)
                                Text(project.displayPath).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(compactTokens(project.totalTokens)).font(.headline.monospacedDigit())
                                if settings.showEstimatedCost, let cost = project.totalCost { Text(currency(cost, language: settings.language)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                            }
                        }
                        .padding(13).pulseSurface()
                    }
                }
            }
        }
    }
    private var projects: [ProjectUsage] {
        let all = filteredAnalytics(state: state, filter: ui.usageProviderFilter).flatMap(\.projects).sorted { $0.totalTokens > $1.totalTokens }
        guard !ui.projectSearch.isEmpty else { return all }
        return all.filter { ($0.name + " " + $0.path).localizedCaseInsensitiveContains(ui.projectSearch) }
    }
}

private struct UsageHeatmapView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var ui = DashboardUIState.shared
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        let calendarDays = days
        let peakTokens = max(1, calendarDays.map(\.tokens).max() ?? 1)
        let selectedDay = ui.selectedUsageDayID.flatMap { id in calendarDays.first { $0.id == id } }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr(settings.language, "Активность по дням", "Daily activity"))
                        .font(.title2.weight(.semibold))
                    Text(tr(
                        settings.language,
                        "Выберите день, чтобы увидеть расход и проекты. Яркость показывает относительный расход за выбранный период.",
                        "Select a day to see usage and projects. Brightness shows relative usage in the selected period."
                    ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                if let selectedDay {
                    dayDetails(selectedDay)
                } else {
                    EmptyDataCard(
                        icon: "calendar.badge.clock",
                        title: tr(settings.language, "За этот период данных нет", "No data for this period"),
                        message: tr(settings.language, "Обновите данные или выберите другой период.", "Refresh the data or choose a different period."),
                        actionTitle: tr(settings.language, "Обновить данные", "Refresh data")
                    ) {
                        Task { await state.refresh(forceAnalytics: true) }
                    }
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(calendarDays) { day in
                        dayButton(day, peakTokens: peakTokens)
                    }
                }

                HStack(spacing: 8) {
                    Text(tr(settings.language, "Меньше токенов", "Fewer tokens"))
                    ForEach(0..<5, id: \.self) { index in
                        Capsule()
                            .fill(Color.pulseTeal.opacity(0.08 + Double(index) * 0.21))
                            .frame(width: 26, height: 8)
                    }
                    Text(tr(settings.language, "Больше", "More"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .pulseSurface()
        .onAppear { selectPreferredDay(from: calendarDays) }
        .onChange(of: settings.usagePeriod) { _ in selectPreferredDay(from: days) }
        .onChange(of: calendarDays.map(\.id)) { _ in
            if ui.selectedUsageDayID.flatMap({ id in days.first { $0.id == id } }) == nil {
                selectPreferredDay(from: days)
            }
        }
    }

    private func dayButton(_ day: Day, peakTokens: Int64) -> some View {
        let selected = ui.selectedUsageDayID == day.id
        return Button {
            ui.selectedUsageDayID = day.id
        } label: {
            VStack(spacing: 3) {
                Text(weekday(day.date)).font(.caption2.weight(.medium))
                Text(dayMonth(day.date))
                    .font(.callout.monospacedDigit().weight(.semibold))
            }
            .foregroundStyle(day.tokens > peakTokens / 2 ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.pulseTeal.opacity(opacity(day.tokens, peakTokens: peakTokens)))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? Color.primary.opacity(0.9) : Color.clear, lineWidth: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(localizedDate(day.date, language: settings.language, dateStyle: .long, timeStyle: .none)): \(compactTokens(day.tokens))")
        .accessibilityLabel(dayAccessibilityLabel(day, selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func dayDetails(_ day: Day) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localizedDate(day.date, language: settings.language, dateStyle: .full, timeStyle: .none))
                        .font(.title3.weight(.semibold))
                    Text(day.tokens == 0
                        ? tr(settings.language, "В этот день расход не зафиксирован", "No usage was recorded on this day")
                        : tr(settings.language, "Локальные агрегаты Codex", "Local Codex aggregates"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !day.receipts.isEmpty {
                    Button {
                        ui.receiptCategory = nil
                        ui.receiptDate = day.date
                        ui.section = .receipts
                    } label: {
                        Label(tr(settings.language, "Открыть историю", "Open history"), systemImage: "arrow.right")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(tr(settings.language, "Покажет записи только за выбранный день", "Shows records for the selected day"))
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                detailTile(tr(settings.language, "Токены", "Tokens"), compactTokens(day.tokens), "number")
                detailTile(tr(settings.language, "Проекты", "Projects"), "\(day.projectCount)", "folder")
                detailTile(tr(settings.language, "Главная модель", "Top model"), day.topModel ?? "—", "cpu")
                if settings.showEstimatedCost {
                    detailTile(tr(settings.language, "Оценка", "Estimate"), day.totalCost.map { currency($0, language: settings.language) } ?? "—", "dollarsign.circle")
                }
            }

            if !day.receipts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr(settings.language, "Проекты в этот день", "Projects on this day"))
                        .font(.headline)
                    ForEach(day.receipts.prefix(4)) { receipt in
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill").foregroundStyle(receipt.provider.tint)
                            Text(receipt.projectName).lineLimit(1)
                            Spacer()
                            Text(compactTokens(receipt.totalTokens)).font(.callout.monospacedDigit().weight(.semibold))
                        }
                        .font(.callout)
                    }
                    if day.receipts.count > 4 {
                        Text(tr(settings.language, "Ещё \(day.receipts.count - 4) — в истории расхода", "\(day.receipts.count - 4) more in usage history"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func detailTile(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit()).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private struct Day: Identifiable {
        let date: Date
        let tokens: Int64
        let totalCost: Double?
        let projectCount: Int
        let topModel: String?
        let receipts: [TaskReceipt]
        var id: String { String(Int(date.timeIntervalSince1970)) }
    }

    private var days: [Day] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -(settings.usagePeriod.rawValue - 1), to: end) else { return [] }
        let sourceDays = filteredAnalytics(state: state, filter: ui.usageProviderFilter).flatMap(\.daily)
        let allReceipts = state.allReceipts.filter { ui.usageProviderFilter.includes($0.provider) }
        var dailyByDate: [Date: [DailyTokenUsage]] = [:]
        var receiptsByDate: [Date: [TaskReceipt]] = [:]

        for sourceDay in sourceDays {
            guard let parsedDate = sourceDay.parsedDate else { continue }
            dailyByDate[calendar.startOfDay(for: parsedDate), default: []].append(sourceDay)
        }
        for receipt in allReceipts {
            receiptsByDate[calendar.startOfDay(for: receipt.date), default: []].append(receipt)
        }

        var result: [Day] = []
        result.reserveCapacity(settings.usagePeriod.rawValue)

        for offset in 0..<settings.usagePeriod.rawValue {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let matchingDays = dailyByDate[date] ?? []
            let receipts = receiptsByDate[date] ?? []
            let costs = matchingDays.compactMap(\.totalCost)
            var modelTotals: [String: Int64] = [:]
            for model in matchingDays.flatMap(\.modelBreakdowns) {
                modelTotals[model.modelName, default: 0] += model.totalTokens
            }
            result.append(Day(
                date: date,
                tokens: matchingDays.reduce(0) { $0 + $1.totalTokens },
                totalCost: costs.isEmpty ? nil : costs.reduce(0, +),
                projectCount: Set(receipts.map { $0.projectPath.isEmpty ? $0.projectName : $0.projectPath }).count,
                topModel: modelTotals.max(by: { $0.value < $1.value })?.key,
                receipts: receipts.sorted { $0.totalTokens > $1.totalTokens }
            ))
        }
        return result
    }

    private func opacity(_ tokens: Int64, peakTokens: Int64) -> Double {
        guard tokens > 0 else { return 0.055 }
        return 0.18 + 0.82 * sqrt(Double(tokens) / Double(peakTokens))
    }

    private func selectPreferredDay(from days: [Day]) {
        ui.selectedUsageDayID = days.last(where: { $0.tokens > 0 })?.id ?? days.last?.id
    }

    private func weekday(_ date: Date) -> String {
        let values = settings.language == .russian
            ? ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
            : ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
        return values[Calendar.current.component(.weekday, from: date) - 1]
    }

    private func dayMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = settings.language.locale
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }

    private func dayAccessibilityLabel(_ day: Day, selected: Bool) -> String {
        let date = localizedDate(day.date, language: settings.language, dateStyle: .long, timeStyle: .none)
        let selection = selected ? tr(settings.language, ", выбрано", ", selected") : ""
        return tr(settings.language, "\(date), \(compactTokens(day.tokens)) токенов\(selection)", "\(date), \(compactTokens(day.tokens)) tokens\(selection)")
    }
}

private struct ReceiptsScreen: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var ui = DashboardUIState.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr(settings.language, "История расхода", "Usage history")).font(.largeTitle.weight(.semibold))
                    Text(tr(
                        settings.language,
                        ui.usageHistoryMode == .tokenReceipts
                            ? "Одна строка — расход проекта за день. Тексты чатов не читаются."
                            : "Локальные снимки процентов и сбросов каждого окна Codex и Claude.",
                        ui.usageHistoryMode == .tokenReceipts
                            ? "One row is one project's usage for one day. Chat text is never read."
                            : "Local percentage and reset snapshots for every Codex and Claude window."
                    ))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if ui.usageHistoryMode == .tokenReceipts && (ui.receiptDate != nil || ui.receiptCategory != nil) {
                    Button(tr(settings.language, "Сбросить фильтры", "Clear filters")) { clearFilters() }
                        .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 12) {
                Picker("", selection: $ui.usageHistoryMode) {
                    Text(tr(settings.language, "Токены по проектам", "Project tokens")).tag(UsageHistoryMode.tokenReceipts)
                    Text(tr(settings.language, "События лимитов", "Quota events")).tag(UsageHistoryMode.quotaEvents)
                }
                .labelsHidden().pickerStyle(.segmented).frame(maxWidth: 520)
                Spacer()
                ProviderFilterPicker(selection: $ui.historyProviderFilter)
            }

            if ui.usageHistoryMode == .quotaEvents {
                QuotaEventHistoryView()
            } else {
            if let date = ui.receiptDate {
                HStack(spacing: 8) {
                    Label(localizedDate(date, language: settings.language, dateStyle: .long, timeStyle: .none), systemImage: "calendar")
                    Button {
                        ui.receiptDate = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .help(tr(settings.language, "Показать все даты", "Show all dates"))
                    .accessibilityLabel(tr(settings.language, "Убрать фильтр по дате", "Clear date filter"))
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Color.pulseTeal.opacity(0.12))
                .clipShape(Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterButton(nil, tr(settings.language, "Все", "All"), count: dateFilteredReceipts.count)
                    ForEach(availableCategories) { item in
                        filterButton(item, L10n.categoryTitle(item, language: settings.language), count: count(for: item))
                    }
                }
                .padding(.vertical, 1)
            }

            if receipts.isEmpty {
                EmptyDataCard(
                    icon: state.allReceipts.isEmpty ? "clock.badge.questionmark" : "line.3.horizontal.decrease.circle",
                    title: state.allReceipts.isEmpty
                        ? tr(settings.language, "История пока пуста", "No usage history yet")
                        : tr(settings.language, "В этом фильтре нет данных", "No data matches this filter"),
                    message: state.allReceipts.isEmpty
                        ? tr(settings.language, "Pulse создаст записи, когда Codex вернёт локальные агрегаты по проектам и дням.", "Pulse creates rows when Codex returns local project-and-day aggregates.")
                        : tr(settings.language, "Выберите другую категорию или покажите всю историю.", "Choose another category or show all history."),
                    actionTitle: state.allReceipts.isEmpty
                        ? tr(settings.language, "Обновить данные", "Refresh data")
                        : tr(settings.language, "Показать всё", "Show all")
                ) {
                    if state.allReceipts.isEmpty {
                        Task { await state.refresh(forceAnalytics: true) }
                    } else {
                        clearFilters()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 10) {
                    historySummaryTile(tr(settings.language, "Записей", "Records"), "\(receipts.count)", "list.number")
                    historySummaryTile(tr(settings.language, "Токены", "Tokens"), compactTokens(receipts.reduce(0) { $0 + $1.totalTokens }), "number")
                    if settings.showEstimatedCost {
                        historySummaryTile(tr(settings.language, "Оценка", "Estimate"), receiptCost.map { currency($0, language: settings.language) } ?? "—", "dollarsign.circle")
                    }
                }

                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(receipts.prefix(150)) { receipt in ReceiptRow(receipt: receipt) }
                    }
                }
            }
            }
        }
        .padding(24)
    }

    private func filterButton(_ value: TaskCategory?, _ title: String, count: Int) -> some View {
        Button("\(title) \(count)") { ui.receiptCategory = value }
            .buttonStyle(.borderedProminent)
            .tint(ui.receiptCategory == value ? Color.pulseTeal : Color.secondary.opacity(0.25))
            .accessibilityLabel("\(title), \(count)")
    }

    private func historySummaryTile(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Color.pulseTeal)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline.monospacedDigit())
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var dateFilteredReceipts: [TaskReceipt] {
        let providerFiltered = state.allReceipts.filter { ui.historyProviderFilter.includes($0.provider) }
        guard let date = ui.receiptDate else { return providerFiltered }
        return providerFiltered.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    private var receipts: [TaskReceipt] {
        guard let category = ui.receiptCategory else { return dateFilteredReceipts }
        return dateFilteredReceipts.filter { $0.category == category }
    }

    private var receiptCost: Double? {
        let costs = receipts.compactMap(\.estimatedCost)
        return costs.isEmpty ? nil : costs.reduce(0, +)
    }

    private func count(for category: TaskCategory) -> Int {
        dateFilteredReceipts.filter { $0.category == category }.count
    }

    private var availableCategories: [TaskCategory] {
        TaskCategory.allCases.filter { count(for: $0) > 0 || ui.receiptCategory == $0 }
    }

    private func clearFilters() {
        ui.receiptCategory = nil
        ui.receiptDate = nil
    }
}

private struct QuotaEventHistoryView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var ui = DashboardUIState.shared

    var body: some View {
        if events.isEmpty {
            EmptyDataCard(
                icon: "clock.badge.questionmark",
                title: tr(settings.language, "Событий лимитов пока нет", "No quota events yet"),
                message: tr(
                    settings.language,
                    "Обновите подключённые сервисы. Pulse сохранит изменения процентов и времени сброса локально.",
                    "Refresh connected providers. Pulse will store percentage and reset changes locally."
                ),
                actionTitle: tr(settings.language, "Обновить данные", "Refresh data")
            ) {
                Task { await state.refresh(forceAnalytics: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    summaryTile(tr(settings.language, "Снимков", "Snapshots"), "\(events.count)", "list.number")
                    summaryTile(tr(settings.language, "Окон", "Windows"), "\(windowCount)", "rectangle.stack")
                    summaryTile(tr(settings.language, "Период", "Period"), "\(settings.usagePeriod.rawValue)d", "calendar")
                }

                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(events.prefix(200)) { event in
                            eventRow(event)
                        }
                    }
                }
            }
        }
    }

    private func eventRow(_ event: Event) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(event.point.provider.tint.opacity(0.13))
                Image(systemName: event.point.provider.symbol).foregroundStyle(event.point.provider.tint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(title(event.point)).font(.headline).lineLimit(1)
                HStack(spacing: 7) {
                    Text(event.point.provider.displayName)
                    Text("· \(localizedDate(event.point.date, language: settings.language, dateStyle: .medium, timeStyle: .short))")
                    if event.resetChanged {
                        Text(tr(settings.language, "· новый период", "· new reset period"))
                            .foregroundStyle(event.point.provider.tint)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(tr(
                    settings.language,
                    "использовано \(percentText(event.point.usedPercent))",
                    "\(percentText(event.point.usedPercent)) used"
                ))
                .font(.headline.monospacedDigit())
                HStack(spacing: 7) {
                    if let delta = event.delta, abs(delta) >= 0.05 {
                        Text(deltaText(delta))
                            .foregroundStyle(delta > 0 ? Color.yellow : Color.pulseGreen)
                    }
                    Text(quotaResetText(event.point.resetsAt, language: settings.language, compact: true))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .pulseSurface()
        .accessibilityElement(children: .combine)
    }

    private func summaryTile(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Color.pulseTeal)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline.monospacedDigit())
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private struct Event: Identifiable {
        let point: QuotaHistoryPoint
        let delta: Double?
        let resetChanged: Bool
        var id: String { point.id }
    }

    private var events: [Event] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -settings.usagePeriod.rawValue, to: .now) ?? .distantPast
        let source = state.quotaHistory
            .filter { $0.date >= cutoff && ui.historyProviderFilter.includes($0.provider) }
            .sorted { $0.date < $1.date }
        var previousByWindow: [String: QuotaHistoryPoint] = [:]
        var result: [Event] = []
        result.reserveCapacity(source.count)
        for point in source {
            let key = "\(point.provider.rawValue)-\(point.windowID)"
            let previous = previousByWindow[key]
            result.append(Event(
                point: point,
                delta: previous.map { point.usedPercent - $0.usedPercent },
                resetChanged: previous.map { resetBoundaryChanged($0.resetsAt, point.resetsAt) } ?? false
            ))
            previousByWindow[key] = point
        }
        return result.sorted { $0.point.date > $1.point.date }
    }

    private var windowCount: Int {
        Set(events.map { "\($0.point.provider.rawValue)-\($0.point.windowID)" }).count
    }

    private func title(_ point: QuotaHistoryPoint) -> String {
        if point.provider == .codex {
            let base = point.title?.isEmpty == false ? point.title! : "Codex"
            return base + " · " + quotaWindowName(point.windowMinutes, language: settings.language)
        }
        return switch point.scope {
        case .session: tr(settings.language, "Текущая сессия", "Current session")
        case .weekly: tr(settings.language, "Все модели · неделя", "All models · week")
        case .modelWeekly:
            (point.title ?? tr(settings.language, "Модель", "Model")) + tr(settings.language, " · неделя", " · week")
        case .other: point.title ?? "Claude"
        }
    }

    private func deltaText(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return tr(
            settings.language,
            "\(sign)\(String(format: "%.1f", value)) п.п.",
            "\(sign)\(String(format: "%.1f", value)) pp"
        )
    }

    private func resetBoundaryChanged(_ previous: Date?, _ current: Date?) -> Bool {
        switch (previous, current) {
        case (nil, nil): false
        case let (previous?, current?): abs(previous.timeIntervalSince(current)) > 90 * 60
        default: true
        }
    }
}

private struct EmptyDataCard: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.pulseTeal)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(Color.pulseTeal)
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 250)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ReceiptRow: View {
    @EnvironmentObject private var settings: SettingsStore
    let receipt: TaskReceipt
    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(receipt.provider.tint.opacity(0.13))
                Image(systemName: receipt.provider.symbol).foregroundStyle(receipt.provider.tint)
            }.frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(receipt.projectName).font(.headline).lineLimit(1)
                HStack(spacing: 7) {
                    Text(L10n.categoryTitle(receipt.category, language: settings.language))
                    if let model = receipt.primaryModel { Text("· \(model)") }
                    Text("· \(localizedDate(receipt.date, language: settings.language, dateStyle: .medium, timeStyle: .none))")
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(compactTokens(receipt.totalTokens)).font(.headline.monospacedDigit())
                HStack(spacing: 7) {
                    Text(tr(settings.language, "кэш \(compactTokens(receipt.cachedTokens))", "cache \(compactTokens(receipt.cachedTokens))"))
                    if settings.showEstimatedCost, let cost = receipt.estimatedCost { Text(currency(cost, language: settings.language)) }
                }.font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(13).pulseSurface()
        .help(receipt.projectPath)
        .accessibilityElement(children: .combine)
    }
}

private struct RouterScreen: View {
    @EnvironmentObject private var settings: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(tr(settings.language, "Маршрут новой задачи", "Route a new task")).font(.largeTitle.weight(.semibold))
            Text(tr(
                settings.language,
                "Codex AI оценивает ближайший шаг, а локальные правила проверяют масштаб, риск и необходимость разбить работу на этапы.",
                "Codex AI evaluates the next step while local guardrails check scale, risk, and whether the work should be split."
            ))
                .foregroundStyle(.secondary)
            TaskRouterCard(expanded: true)
            Spacer()
        }.padding(24)
    }
}

private struct TaskRouterCard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore
    var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(tr(settings.language, "Рекомендация для задачи", "Task recommendation")).font(.headline)
                Spacer()
                Label(tr(settings.language, "Без автозапуска", "No auto-run"), systemImage: "hand.raised")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if expanded {
                HStack(alignment: .center, spacing: 12) {
                    Picker("", selection: $state.routeMode) {
                        ForEach(RouterAnalysisMode.allCases) { mode in
                            Text(L10n.routeModeTitle(mode, language: settings.language)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 270)

                    Label(
                        state.routeMode == .ai
                            ? tr(settings.language, "Короткий запрос к Codex · расходует немного квоты · Pulse не сохраняет текст", "Short Codex request · uses a small amount of quota · Pulse does not save the text")
                            : tr(settings.language, "Мгновенно и без расхода квоты, но менее точно для неоднозначных задач", "Instant and quota-free, but less precise for ambiguous tasks"),
                        systemImage: state.routeMode == .ai ? "brain.head.profile" : "lock.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                TextField(tr(settings.language, "Опишите задачу…", "Describe the task…"), text: $state.taskText, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(expanded ? 6 : 2).onSubmit { state.routeCurrentTask() }
                Button { state.routeCurrentTask() } label: {
                    Label(
                        state.routeMode == .ai
                            ? tr(settings.language, "Спросить Codex", "Ask Codex")
                            : tr(settings.language, "Проверить", "Check"),
                        systemImage: state.routeMode == .ai ? "sparkles" : "bolt"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.pulseTeal)
                .disabled(state.taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isRoutingTask)
            }

            if state.isRoutingTask {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text(tr(
                        settings.language,
                        "Локальный маршрут уже готов · Codex уточняет детали в фоне…",
                        "The local route is ready · Codex is refining details in the background…"
                    ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }

            if let recommendation = state.recommendation {
                Divider()

                HStack(spacing: 8) {
                    statusPill(
                        L10n.routeSourceTitle(recommendation.source, language: settings.language),
                        icon: recommendation.source == .codexAI ? "brain.head.profile" : "shield.lefthalf.filled",
                        color: recommendation.source == .codexAI ? Color.pulseTeal : Color.secondary
                    )
                    statusPill(
                        L10n.routeTaskShapeTitle(recommendation.taskShape, language: settings.language),
                        icon: "point.3.connected.trianglepath.dotted",
                        color: .purple
                    )
                    Spacer()
                    Text(tr(
                        settings.language,
                        "Уверенность: \(L10n.routeConfidenceTitle(recommendation.confidence, language: settings.language))",
                        "Confidence: \(L10n.routeConfidenceTitle(recommendation.confidence, language: settings.language))"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: expanded ? 190 : 150), spacing: 10)], alignment: .leading, spacing: 10) {
                    recommendationTile(
                        icon: modelIcon(recommendation.model),
                        title: recommendation.model.rawValue,
                        subtitle: "effort · \(recommendation.effort.rawValue)",
                        color: modelColor(recommendation.model)
                    )
                    recommendationTile(
                        icon: recommendation.provider.symbol,
                        title: recommendation.provider.displayName,
                        subtitle: L10n.estimateTitle(recommendation.estimate, language: settings.language),
                        color: recommendation.provider.tint
                    )
                    if let low = recommendation.estimatedTokensLow, let high = recommendation.estimatedTokensHigh {
                        recommendationTile(icon: "chart.bar.fill", title: "\(compactTokens(low))–\(compactTokens(high))", subtitle: tr(settings.language, "похожие проект-дни", "similar project-days"), color: .purple)
                    }
                }

                Text(settings.language == .russian ? recommendation.rationaleRU : recommendation.rationaleEN)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if recommendation.needsSplit {
                    if expanded {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(
                                tr(settings.language, "Лучше разбить на этапы", "Split this into stages"),
                                systemImage: "square.split.2x1"
                            )
                            .font(.headline)
                            .foregroundStyle(Color.pulseTeal)

                            ForEach(Array(recommendation.stages.enumerated()), id: \.offset) { index, stage in
                                HStack(alignment: .top, spacing: 11) {
                                    Text("\(index + 1)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(Color.pulseTeal)
                                        .clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(settings.language == .russian ? stage.titleRU : stage.titleEN)
                                            .font(.callout.weight(.medium))
                                        Text("\(stage.model.rawValue) · effort \(stage.effort.rawValue)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(13)
                        .background(Color.pulseTeal.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        Label(
                            tr(settings.language, "Разбить на \(recommendation.stages.count) этапа — откройте «Маршрут задачи»", "Split into \(recommendation.stages.count) stages — open Task route"),
                            systemImage: "square.split.2x1"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.pulseTeal)
                    }
                }
            }
        }
        .padding(16).pulseSurface()
    }
    private func recommendationTile(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.title3.weight(.semibold)); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }.padding(10).background(color.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private func statusPill(_ title: String, icon: String, color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.09))
            .clipShape(Capsule())
    }
    private func modelIcon(_ value: RouterModel) -> String { value == .sol ? "sun.max.fill" : (value == .terra ? "globe.americas.fill" : "moon.stars.fill") }
    private func modelColor(_ value: RouterModel) -> Color { value == .sol ? .pulseOrange : (value == .terra ? .pulseTeal : .pulseGreen) }
}
