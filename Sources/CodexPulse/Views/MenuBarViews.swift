import AppKit
import Charts
import SwiftUI

struct MenuBarLabelView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Group {
            switch settings.menuBarStyle {
            case .pulse:
                Image(systemName: "waveform.path.ecg")
            case .percentage:
                providerPercentages
            case .dual:
                HStack(spacing: 4) {
                    Image(systemName: "waveform.path.ecg")
                    if state.claude.state == .connected {
                        Text("C \(compact(state.codex.remainingPercent)) · A \(compact(state.claude.remainingPercent))")
                    } else {
                        Text(compact(state.codex.remainingPercent))
                    }
                }
            case .smart:
                HStack(spacing: 4) {
                    providerPercentages
                    Image(systemName: paceSymbol)
                        .accessibilityHidden(true)
                }
            case .today:
                HStack(spacing: 4) {
                    Image(systemName: "waveform.path.ecg")
                    Text(compactTokens(state.todayTokens))
                }
            case .pace:
                HStack(spacing: 4) {
                    Image(systemName: "waveform.path.ecg")
                    Text(paceLabel)
                }
            }
        }
        .help(menuBarSummary)
        .accessibilityLabel(menuBarSummary)
    }

    private var providerPercentages: some View {
        Image(nsImage: MenuBarProviderImage.make(
            codex: compact(state.codex.remainingPercent),
            claude: compact(state.claude.remainingPercent),
            textColor: colorScheme == .dark ? .white : .black
        ))
        .renderingMode(.original)
        .accessibilityHidden(true)
        .id("\(compact(state.codex.remainingPercent))-\(compact(state.claude.remainingPercent))-\(colorScheme == .dark ? "dark" : "light")")
    }

    private func compact(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    private var paceSymbol: String {
        switch state.healthLevel {
        case .healthy: "checkmark"
        case .watch: "arrow.up.right"
        case .critical: "exclamationmark"
        case .unknown: "ellipsis"
        }
    }

    private var paceLabel: String {
        switch state.healthLevel {
        case .healthy: tr(settings.language, "норма", "safe")
        case .watch: tr(settings.language, "быстро", "fast")
        case .critical: tr(settings.language, "мало", "low")
        case .unknown: "—"
        }
    }

    private var menuBarSummary: String {
        let providerStatus = state.connectedSnapshots.map { snapshot in
            tr(
                settings.language,
                "\(snapshot.provider.displayName): осталось \(percentText(snapshot.remainingPercent))",
                "\(snapshot.provider.displayName): \(percentText(snapshot.remainingPercent)) left"
            )
        }
        guard !providerStatus.isEmpty else {
            return tr(settings.language, "Codex Pulse: данные обновляются", "Codex Pulse: updating data")
        }
        return providerStatus.joined(separator: ". ")
    }
}

private enum MenuBarProviderImage {
    private static let height: CGFloat = 18
    private static let iconSize: CGFloat = 16
    private static let inset: CGFloat = 1
    private static let gap: CGFloat = 4
    private static let separator = "·"

    static func make(codex: String, claude: String, textColor: NSColor) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]
        let codexWidth = textWidth(codex, attributes: attributes)
        let separatorWidth = textWidth(separator, attributes: attributes)
        let claudeWidth = textWidth(claude, attributes: attributes)
        let width = inset + iconSize + gap + codexWidth + gap + separatorWidth + gap + iconSize + gap + claudeWidth + inset
        let image = NSImage(size: NSSize(width: ceil(width), height: height))
        image.isTemplate = false

        image.lockFocus()
        var x = inset
        drawAsset(named: "CodexStatusIcon", in: NSRect(x: x, y: inset, width: iconSize, height: iconSize))
        x += iconSize + gap
        draw(codex, at: x, width: codexWidth, attributes: attributes)
        x += codexWidth + gap
        draw(separator, at: x, width: separatorWidth, attributes: attributes)
        x += separatorWidth + gap
        drawAsset(named: "ClaudeStatusIcon", in: NSRect(x: x, y: inset, width: iconSize, height: iconSize))
        x += iconSize + gap
        draw(claude, at: x, width: claudeWidth, attributes: attributes)
        image.unlockFocus()

        return image
    }

    private static func textWidth(_ value: String, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        ceil((value as NSString).size(withAttributes: attributes).width)
    }

    private static func draw(_ value: String, at x: CGFloat, width: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        (value as NSString).draw(
            in: NSRect(x: x, y: 0, width: width, height: height),
            withAttributes: attributes
        )
    }

    private static func drawAsset(named name: String, in rect: NSRect) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let asset = NSImage(contentsOf: url)
        else { return }
        asset.draw(in: rect)
    }
}

struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var ui = MenuBarUIState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 12)
            Picker("", selection: $ui.tab) {
                Text(tr(settings.language, "Обзор", "Overview")).tag(MenuPanelTab.overview)
                Text(tr(settings.language, "Токены AI", "AI tokens")).tag(MenuPanelTab.usage)
                Text(tr(settings.language, "Сигналы", "Signals")).tag(MenuPanelTab.signals)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal, 18)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                Group {
                    switch ui.tab {
                    case .overview: overview
                    case .usage: usage
                    case .signals: signals
                    }
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            actions.padding(14)
        }
        .frame(width: 420, height: panelHeight, alignment: .top)
        .background(panelBackground)
    }

    private var panelHeight: CGFloat {
        let available = NSScreen.main?.visibleFrame.height ?? 800
        return min(720, max(480, available - 72))
    }

    private var header: some View {
        HStack {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.pulseTeal.opacity(0.14))
                Image(systemName: "waveform.path.ecg").foregroundStyle(Color.pulseTeal)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Codex Pulse").font(.headline.weight(.semibold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(connectionColor(state.codex.state))
                        .frame(width: 6, height: 6)
                Text(codexPlanName(state.codexAccountDetails.planType, language: settings.language)
                         ?? tr(settings.language, "Codex подключён локально", "Codex connected locally"))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if state.showsRefreshIndicator { ProgressView().controlSize(.mini) }
            if let updated = state.lastUpdated {
                Text(tr(settings.language, "Обновлено ", "Updated ") + localizedDate(updated, language: settings.language, dateStyle: .none, timeStyle: .short))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            providerOverviewCard(.codex)
            if state.claude.state == .connected || settings.showUnavailableProviders {
                providerOverviewCard(.claude)
            }
            serviceStatus
        }
    }

    private var usage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle").foregroundStyle(Color.pulseTeal)
                Text(tr(
                    settings.language,
                    "Здесь показаны локальные токены Codex и Claude Code. Claude Web отдаёт только лимиты и сбросы; выберите источник ниже.",
                    "This view shows local Codex and Claude Code tokens. Claude Web exposes quotas and resets only; choose a source below."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Picker("", selection: $ui.usageProvider) {
                Text("Codex").tag(ProviderKind.codex)
                Text("Claude Code").tag(ProviderKind.claude)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            summaryMetrics
            if !menuAnalytics.daily.isEmpty {
                menuCard {
                    HStack {
                        Label(tr(settings.language, "Динамика расхода", "Usage trend"), systemImage: "chart.bar.xaxis")
                            .font(.callout.weight(.semibold))
                        Spacer()
                        Text("\(settings.usagePeriod.rawValue)d")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    MenuUsageChart(days: menuAnalytics.daily).frame(height: 116)
                }
            }
            modelRankingSection(menuAnalytics.modelUsageBreakdown)
            rankingSection(
                title: tr(settings.language, "Проекты", "Projects"),
                icon: "folder",
                rows: Array(menuAnalytics.projects.sorted { $0.totalTokens > $1.totalTokens }.prefix(4)).map { ($0.name, compactTokens($0.totalTokens), $0.totalCost) }
            )
            HStack {
                Label(tr(settings.language, "Проект-дни", "Project-days"), systemImage: "list.bullet.rectangle")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("\(menuAnalytics.recentReceipts.count)").font(.callout.monospacedDigit())
            }
            Text(tr(settings.language, "Pulse группирует агрегаты по проекту и дню — без чтения текстов чатов.", "Pulse groups aggregates by project and day without reading chat text."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var signals: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr(
                settings.language,
                "Ранние сигналы о возможном сбросе лимитов — отдельно от обновления квот и токенов.",
                "Early signals about possible quota resets, separate from refreshing quotas and tokens."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            ResetSignalCard()
        }
    }

    @ViewBuilder
    private func providerOverviewCard(_ provider: ProviderKind) -> some View {
        let snapshot = provider == .codex ? state.codex : state.claude
        menuCard {
            HStack {
                providerConnectionRow(snapshot)
                Spacer()
                if provider == .codex, let reset = snapshot.quota?.resetsAt {
                    Text(quotaResetText(reset, language: settings.language, compact: true))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                } else if provider == .claude, let plan = state.claudeAccountDetails.planName {
                    Text(plan).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            if snapshot.state == .connected {
                Divider()
                if provider == .codex {
                    quotaSection
                } else {
                    claudeQuotaSection
                }
                providerPaceCard(provider)
                providerQuotaTrend(provider)
            } else if let message = snapshot.message {
                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func providerConnectionRow(_ snapshot: ProviderSnapshot) -> some View {
        HStack(spacing: 7) {
            Image(systemName: snapshot.provider.symbol).foregroundStyle(snapshot.provider.tint)
            Text(snapshot.provider.displayName).font(.callout.weight(.semibold))
            Circle().fill(connectionColor(snapshot.state)).frame(width: 7, height: 7)
            if snapshot.state != .connected {
                Text(tr(settings.language, "не подключён", "not connected"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(quotaMeters.prefix(4)) { meter in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
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
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if quotaMeters.isEmpty {
                Text(state.codex.message ?? tr(settings.language, "Данные квоты пока недоступны", "Quota data is not available yet"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let balance = state.codexAccountDetails.creditBalance, balance != "0" {
                HStack {
                    Label(tr(settings.language, "Кредиты", "Credits"), systemImage: "creditcard")
                    Spacer()
                    Text(balance).monospacedDigit()
                }
                .font(.caption)
            }
        }
    }

    private var quotaMeters: [QuotaMeterItem] {
        let values = codexQuotaMeters(state.codexAccountDetails, language: settings.language)
        if !values.isEmpty { return values }
        guard let quota = state.codex.quota else { return [] }
        return [QuotaMeterItem(id: "codex-fallback", title: "Codex", window: quota)]
    }

    private var claudeQuotaSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(claudeQuotaMeters(state.claudeAccountDetails, language: settings.language).prefix(4)) { meter in
                ClaudeQuotaMeterView(meter: meter, language: settings.language, compact: true)
            }
            if let balance = state.claudeAccountDetails.creditBalance {
                HStack {
                    Label(tr(settings.language, "Usage credits", "Usage credits"), systemImage: "creditcard")
                    Spacer()
                    Text(balance).monospacedDigit()
                }
                .font(.caption)
            }
        }
    }

    private func providerPaceCard(_ provider: ProviderKind) -> some View {
        let insight = state.pace[provider] ?? .unknown
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Circle().fill(insight.level.color).frame(width: 8, height: 8)
                Text(healthTitle(for: insight.level)).font(.callout.weight(.semibold))
                Spacer()
                Text(quotaForecastText(insight, language: settings.language, compact: true))
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.primary)
            }
            if let safe = insight.safePercentToday {
                Text(tr(settings.language, "Сегодня безопасно потратить не более \(Int(safe.rounded()))%", "Safe to use today: no more than \(Int(safe.rounded()))%"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(insight.level.color.opacity(colorScheme == .dark ? 0.16 : 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func providerQuotaTrend(_ provider: ProviderKind) -> some View {
        let trend = quotaTrend(for: provider)
        if !trend.points.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tr(settings.language, "Остаток лимита · \(settings.usagePeriod.rawValue) дней", "Quota remaining · \(settings.usagePeriod.rawValue) days"))
                            .font(.caption.weight(.semibold))
                        Text(trend.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if let latest = trend.points.last {
                        Text(percentText(latest.remainingPercent))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(provider.tint)
                    }
                }
                MenuQuotaChart(points: trend.points, tint: provider.tint).frame(height: 72)
            }
            .padding(.top, 2)
        } else {
            HStack(spacing: 7) {
                Image(systemName: "chart.xyaxis.line").foregroundStyle(provider.tint)
                Text(tr(
                    settings.language,
                    "Динамика лимита появится после следующих обновлений.",
                    "Quota history will appear after the next updates."
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func quotaTrend(for provider: ProviderKind) -> (title: String, points: [QuotaHistoryPoint]) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -settings.usagePeriod.rawValue, to: .now) ?? .distantPast
        let points = state.quotaHistory.filter { $0.provider == provider && $0.date >= cutoff }
        let groups = Dictionary(grouping: points, by: \.windowID)
        guard let selected = groups.values.max(by: { lhs, rhs in
            (lhs.last?.usedPercent ?? 0) < (rhs.last?.usedPercent ?? 0)
        })?.sorted(by: { $0.date < $1.date }), let latest = selected.last else {
            return ("", [])
        }
        return (quotaTrendTitle(latest), selected)
    }

    private func quotaTrendTitle(_ point: QuotaHistoryPoint) -> String {
        if point.provider == .codex {
            let base = point.title?.isEmpty == false ? point.title! : "Codex"
            return base + " · " + quotaWindowName(point.windowMinutes, language: settings.language)
        }
        return switch point.scope {
        case .session: tr(settings.language, "Текущая сессия", "Current session")
        case .weekly: tr(settings.language, "Все модели · неделя", "All models · week")
        case .modelWeekly: (point.title ?? "Claude") + tr(settings.language, " · неделя", " · week")
        case .other: point.title ?? "Claude"
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var summaryMetrics: some View {
        HStack(spacing: 8) {
            metric(tr(settings.language, "Сегодня", "Today"), compactTokens(tokensToday))
            metric(tr(settings.language, "За период", "Period"), compactTokens(menuAnalytics.totals.totalTokens))
            if settings.showEstimatedCost {
                metric(tr(settings.language, "Оценка", "Estimate"), menuAnalytics.totals.totalCost.map { currency($0, language: settings.language) } ?? "—")
            }
        }
    }

    private var menuAnalytics: UsageAnalyticsSnapshot {
        ui.usageProvider == .codex ? state.codexAnalytics : state.claudeAnalytics
    }

    private var tokensToday: Int64 {
        menuAnalytics.daily.last.flatMap { day in
            day.parsedDate.map(Calendar.current.isDateInToday) == true ? day.totalTokens : nil
        } ?? 0
    }

    private func rankingSection(title: String, icon: String, rows: [(String, String, Double?)]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon).font(.callout.weight(.semibold))
            if rows.isEmpty {
                Text(tr(settings.language, "Пока нет данных", "No data yet")).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(row.0).lineLimit(1)
                        Spacer()
                        Text(row.1).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        if settings.showEstimatedCost, let cost = row.2 {
                            Text(currency(cost, language: settings.language)).font(.caption.monospacedDigit()).frame(width: 64, alignment: .trailing)
                        }
                    }
                    .font(.caption)
                }
            }
        }
        .padding(12)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func modelRankingSection(_ breakdown: ModelUsageBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(tr(settings.language, "Модели", "Models"), systemImage: "cpu")
                .font(.callout.weight(.semibold))
            if breakdown.insights.isEmpty {
                Text(tr(settings.language, "Пока нет данных", "No data yet"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(breakdown.insights.prefix(4))) { model in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.modelName).lineLimit(1)
                            if let project = model.topProjectName {
                                Text(tr(settings.language, "Больше всего: ", "Most in: ") + project)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int((model.shareOfAttributedTokens * 100).rounded()))% · \(compactTokens(model.totalTokens))")
                                .font(.caption.monospacedDigit())
                            if settings.showEstimatedCost, let cost = model.cost {
                                Text(currency(cost, language: settings.language)).font(.caption.monospacedDigit())
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                Text(
                    breakdown.hasCompleteCoverage
                        ? tr(settings.language, "Доли — от локальных токенов, не от квоты.", "Shares are local tokens, not quota.")
                        : tr(settings.language, "Модель определена для \(Int((breakdown.coverage * 100).rounded()))% локальных токенов.", "A model is known for \(Int((breakdown.coverage * 100).rounded()))% of local tokens.")
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func menuCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(12)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        }
    }

    private var panelBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.075, green: 0.086, blue: 0.102)
            : Color(red: 0.965, green: 0.972, blue: 0.982)
    }

    private var cardFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.075) : Color.black.opacity(0.055)
    }

    private var cardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.10)
    }

    @ViewBuilder
    private var serviceStatus: some View {
        if let status = state.serviceHealth[.codex] {
            HStack(spacing: 7) {
                Circle().fill(statusColor(status.state)).frame(width: 7, height: 7)
                Text(tr(settings.language, "Статус OpenAI", "OpenAI status")).font(.caption.weight(.semibold))
                Spacer()
                Text(status.message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { openDashboard(.overview) } label: {
                Label(tr(settings.language, "Открыть", "Open"), systemImage: "rectangle.on.rectangle")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.pulseTeal)

            Button {
                settings.showFloatingWidget = true
                FloatingPanelController.shared.showAndFocus()
            } label: {
                Label(tr(settings.language, "Виджет", "Widget"), systemImage: "macwindow.on.rectangle")
            }
            .buttonStyle(.bordered)
            Button { openDashboard(.usage) } label: {
                Label(tr(settings.language, "История", "History"), systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.bordered)
            Button {
                ui.tab = .signals
                Task { await state.refreshResetSignals() }
            } label: {
                if state.isCheckingResetSignals {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "bell.badge")
                }
            }
            .buttonStyle(.bordered)
            .disabled(state.isCheckingResetSignals || !settings.resetSignalChecksEnabled)
            .help(tr(settings.language, "Проверить сигналы о сбросе", "Check reset signals"))
            .accessibilityLabel(tr(settings.language, "Проверить сигналы о сбросе", "Check reset signals"))
            Spacer()
            Menu {
                Button(tr(settings.language, "Настройки", "Settings")) { openDashboard(.settings) }
                Divider()
                Button(tr(settings.language, "Выйти из Codex Pulse", "Quit Codex Pulse")) {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .accessibilityLabel(tr(settings.language, "Меню настроек", "Settings menu"))
            Button {
                Task { await state.refresh(forceAnalytics: true) }
            } label: {
                HStack(spacing: 6) {
                    if state.showsRefreshIndicator {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(tr(settings.language, "Обновить", "Refresh"))
                }
            }
            .buttonStyle(.bordered)
            .disabled(state.showsRefreshIndicator)
            .keyboardShortcut("r", modifiers: .command)
            .help(tr(settings.language, "Обновить квоты и статистику", "Refresh quotas and usage"))
            .accessibilityLabel(tr(settings.language, "Обновить данные", "Refresh data"))
        }
    }

    private func openDashboard(_ section: DashboardSection) {
        DashboardUIState.shared.section = section
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "dashboard")
    }

    private func healthTitle(for level: HealthLevel) -> String {
        switch level {
        case .healthy: tr(settings.language, "Темп нормальный", "Pace is healthy")
        case .watch: tr(settings.language, "Расход выше безопасного", "Usage is above budget")
        case .critical: tr(settings.language, "Запас заканчивается", "Quota is running low")
        case .unknown: tr(settings.language, "Собираем данные", "Waiting for data")
        }
    }

    private func statusColor(_ value: ServiceHealthState) -> Color {
        switch value {
        case .operational: .pulseGreen
        case .degraded: .yellow
        case .outage: .red
        case .unknown: .secondary
        }
    }

    private func connectionColor(_ value: ProviderConnectionState) -> Color {
        switch value {
        case .connected: .pulseGreen
        case .loading: .yellow
        case .unavailable: .secondary
        case .error: .red
        }
    }
}

private enum MenuPanelTab: Hashable {
    case overview
    case usage
    case signals
}

@MainActor
private final class MenuBarUIState: ObservableObject {
    static let shared = MenuBarUIState()
    @Published var tab: MenuPanelTab = .overview
    @Published var usageProvider: ProviderKind = .codex
}

private struct MenuUsageChart: View {
    let days: [DailyTokenUsage]

    var body: some View {
        Chart(days) { day in
            BarMark(
                x: .value("Date", day.parsedDate ?? .now),
                y: .value("Tokens", day.totalTokens)
            )
            .foregroundStyle(Color.pulseTeal.gradient)
            .cornerRadius(3)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityLabel("Daily Codex token usage")
    }
}

private struct MenuQuotaChart: View {
    let points: [QuotaHistoryPoint]
    let tint: Color

    var body: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value("Remaining", point.remainingPercent)
            )
            .foregroundStyle(tint)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            PointMark(
                x: .value("Date", point.date),
                y: .value("Remaining", point.remainingPercent)
            )
            .foregroundStyle(tint)
            .symbolSize(points.count == 1 ? 32 : 14)
        }
        .chartYScale(domain: 0 ... 100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityLabel("Quota remaining history")
    }
}
