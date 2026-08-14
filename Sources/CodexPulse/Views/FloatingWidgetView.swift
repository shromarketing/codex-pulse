import Charts
import SwiftUI

struct FloatingWidgetView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore
    @State private var selectedProvider: ProviderKind = .codex

    var body: some View {
        GeometryReader { proxy in
            let layout = WidgetLayout(size: proxy.size)
            Group {
                switch layout {
                case .mini:
                    mini
                case .compact:
                    compact
                case .focus:
                    focus(size: proxy.size)
                case .expanded:
                    expanded(size: proxy.size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .environment(\.locale, settings.language.locale)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Codex Pulse")
        .onChange(of: state.claude.state) { connectionState in
            if connectionState != .connected, selectedProvider == .claude {
                selectedProvider = .codex
            }
        }
    }

    private var mini: some View {
        HStack(spacing: 7) {
            compactProviderButton(.codex, snapshot: state.codex)
            if shouldShowClaude {
                compactProviderButton(.claude, snapshot: state.claude)
            }
            Spacer(minLength: 0)
            HStack(spacing: 7) {
                refreshButton
                expandButton(isExpanded: false)
            }
        }
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .help(widgetSummary)
    }

    private var compact: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                compactProviderButton(.codex, snapshot: state.codex)
                if shouldShowClaude {
                    compactProviderButton(.claude, snapshot: state.claude)
                }
                Spacer(minLength: 2)
                widgetControls(isExpanded: false)
            }
            Text(selectedResetText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Circle().fill(selectedHealthLevel.color).frame(width: 7, height: 7)
                    Text(selectedPaceTitle).font(.caption.weight(.semibold))
                }
                Text(quotaForecastText(selectedInsight, language: settings.language, compact: true))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(selectedHealthLevel.color)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func focus(size: CGSize) -> some View {
        VStack(spacing: 0) {
            widgetHeader(isExpanded: true)
            Divider().opacity(0.5)
            ScrollView(.vertical) {
                VStack(spacing: 10) {
                    quotaSummary(showAllWindows: true)
                    metricRow
                    intelligenceRow
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.automatic)
        }
    }

    private func expanded(size: CGSize) -> some View {
        VStack(spacing: 0) {
            widgetHeader(isExpanded: true)
            Divider().opacity(0.5)
            ScrollView(.vertical) {
                VStack(spacing: 10) {
                    quotaSummary(showAllWindows: true)
                    metricRow

                    if !state.codexAnalytics.daily.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(tr(settings.language, "Расход", "Usage"), systemImage: "chart.bar.xaxis")
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text("\(settings.usagePeriod.rawValue)d")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            WidgetUsageChart(days: state.codexAnalytics.daily)
                                .frame(height: chartHeight(for: size))
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    intelligenceRow
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.automatic)
        }
    }

    private func widgetHeader(isExpanded: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "waveform.path.ecg")
                .foregroundStyle(Color.pulseTeal)
            VStack(alignment: .leading, spacing: 1) {
                Text("Codex Pulse").font(.headline)
                Text(widgetProviderSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            widgetControls(isExpanded: isExpanded)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func quotaSummary(showAllWindows: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !codexWidgetMeters.isEmpty {
                providerQuotaGroup(
                    provider: .codex,
                    meters: codexWidgetMeters,
                    showAllWindows: showAllWindows
                )
            }
            if !claudeWidgetMeters.isEmpty {
                providerQuotaGroup(
                    provider: .claude,
                    meters: claudeWidgetMeters,
                    showAllWindows: showAllWindows
                )
            }
            if widgetQuotaMeters.isEmpty {
                Text(tr(settings.language, "Данные квоты пока недоступны", "Quota data is not available yet"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        }
    }

    private func providerQuotaGroup(
        provider: ProviderKind,
        meters: [QuotaMeterItem],
        showAllWindows: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 9) {
                Label(provider.displayName, systemImage: provider.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(provider.tint)

                ForEach(Array(meters.prefix(showAllWindows ? 6 : 2).enumerated()), id: \.element.id) { index, meter in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(meterTitle(meter, provider: provider))
                                .font(index == 0 ? .callout.weight(.semibold) : .caption.weight(.semibold))
                                .lineLimit(1)
                            Spacer()
                            Text(percentText(meter.window.remainingPercent))
                                .font(index == 0 ? .title3.monospacedDigit().weight(.semibold) : .callout.monospacedDigit().weight(.semibold))
                        }
                        ProgressView(value: meter.window.remainingPercent, total: 100)
                            .tint(provider == .claude ? Color.pulseOrange : (index == 0 ? Color.pulseTeal : Color.pulseGreen))
                            .accessibilityLabel(tr(
                                settings.language,
                                "Осталось \(percentText(meter.window.remainingPercent)). \(quotaResetText(meter.window.resetsAt, language: settings.language))",
                                "\(percentText(meter.window.remainingPercent)) left. \(quotaResetText(meter.window.resetsAt, language: settings.language))"
                            ))
                        Text(quotaResetText(meter.window.resetsAt, language: settings.language))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if showAllWindows, index < min(meters.count, 6) - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
            .padding(11)
            .background(Color.primary.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            }

            providerPaceSummary(provider)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func providerPaceSummary(_ provider: ProviderKind) -> some View {
        let insight = state.pace[provider]
        let level = insight?.level ?? .unknown
        return VStack(alignment: .leading, spacing: 5) {
            Label(
                provider.displayName + " · " + healthTitle(for: level),
                systemImage: healthSymbol(for: level)
            )
                .font(.caption.weight(.semibold))
                .foregroundStyle(level.color)
            Text(quotaForecastText(insight, language: settings.language, compact: true))
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(level.color)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let insight {
                paceLine(insight)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(level.color.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func meterTitle(_ meter: QuotaMeterItem, provider: ProviderKind) -> String {
        let prefix = provider.displayName + " · "
        guard meter.title.hasPrefix(prefix) else { return meter.title }
        return String(meter.title.dropFirst(prefix.count))
    }

    private var metricRow: some View {
        HStack(spacing: 8) {
            widgetMetric(tr(settings.language, "Сегодня", "Today"), compactTokens(state.todayTokens))
            widgetMetric(tr(settings.language, "Период", "Period"), compactTokens(state.codexAnalytics.totals.totalTokens))
            if settings.showEstimatedCost {
                widgetMetric(
                    tr(settings.language, "Оценка", "Estimate"),
                    state.todayCost.map { currency($0, language: settings.language) } ?? "—"
                )
            }
        }
    }

    private func widgetMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.monospacedDigit().weight(.semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var intelligenceRow: some View {
        HStack(spacing: 10) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr(settings.language, "Топ-модель", "Top model")).font(.caption2).foregroundStyle(.secondary)
                    Text(state.codexAnalytics.modelTotals.first?.modelName ?? "—").font(.caption.weight(.semibold)).lineLimit(1)
                }
            } icon: {
                Image(systemName: "cpu")
            }
            Spacer()
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr(settings.language, "Топ-проект", "Top project")).font(.caption2).foregroundStyle(.secondary)
                    Text(topProjectName).font(.caption.weight(.semibold)).lineLimit(1)
                }
            } icon: {
                Image(systemName: "folder")
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private func compactProviderButton(_ provider: ProviderKind, snapshot: ProviderSnapshot) -> some View {
        let isSelected = activeProvider == provider
        return Button {
            selectedProvider = provider
        } label: {
            HStack(spacing: 4) {
                Image(systemName: provider.symbol)
                    .foregroundStyle(provider.tint)
                if isSelected {
                    Text(provider.displayName)
                        .font(.caption.weight(.semibold))
                }
                Text(percentText(snapshot.remainingPercent))
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 26)
            .background(isSelected ? provider.tint.opacity(0.16) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(provider == .claude && state.claude.state != .connected)
        .help(tr(
            settings.language,
            "Показать лимит и темп \(provider.displayName)",
            "Show \(provider.displayName) quota and pace"
        ))
        .accessibilityLabel(tr(
            settings.language,
            "\(provider.displayName), осталось \(percentText(snapshot.remainingPercent))",
            "\(provider.displayName), \(percentText(snapshot.remainingPercent)) left"
        ))
        .accessibilityValue(isSelected
                            ? tr(settings.language, "выбран", "selected")
                            : tr(settings.language, "не выбран", "not selected"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func widgetControls(isExpanded: Bool) -> some View {
        HStack(spacing: 9) {
            refreshButton
            expandButton(isExpanded: isExpanded)
            Button {
                settings.showFloatingWidget = false
                state.syncFloatingPanel()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help(tr(settings.language, "Скрыть виджет", "Hide widget"))
        }
    }

    private func expandButton(isExpanded: Bool) -> some View {
        Button {
            FloatingPanelController.shared.toggleExpanded(isCurrentlyExpanded: isExpanded)
        } label: {
            Image(systemName: isExpanded
                  ? "arrow.down.right.and.arrow.up.left"
                  : "arrow.up.left.and.arrow.down.right")
        }
        .buttonStyle(.plain)
        .help(isExpanded
              ? tr(settings.language, "Свернуть виджет", "Collapse widget")
              : tr(settings.language, "Развернуть виджет", "Expand widget"))
        .accessibilityLabel(isExpanded
                            ? tr(settings.language, "Свернуть виджет", "Collapse widget")
                            : tr(settings.language, "Развернуть виджет", "Expand widget"))
    }

    private var refreshButton: some View {
        Button {
            Task { await state.refresh(forceAnalytics: true) }
        } label: {
            if state.showsRefreshIndicator {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .buttonStyle(.plain)
        .disabled(state.showsRefreshIndicator)
        .help(tr(settings.language, "Обновить данные", "Refresh data"))
        .accessibilityLabel(state.showsRefreshIndicator
                            ? tr(settings.language, "Данные обновляются", "Refreshing data")
                            : tr(settings.language, "Обновить данные", "Refresh data"))
    }

    private var codexWidgetMeters: [QuotaMeterItem] {
        var values = codexQuotaMeters(state.codexAccountDetails, language: settings.language)
        if values.isEmpty, let quota = state.codex.quota {
            values = [QuotaMeterItem(id: "codex-fallback", title: "Codex", window: quota)]
        }
        return values
    }

    private var claudeWidgetMeters: [QuotaMeterItem] {
        guard state.claude.state == .connected else { return [] }
        return claudeQuotaMeters(
            state.claudeAccountDetails,
            language: settings.language,
            includeProvider: false
        )
    }

    private var widgetQuotaMeters: [QuotaMeterItem] {
        codexWidgetMeters + claudeWidgetMeters
    }

    private var topProjectName: String {
        state.codexAnalytics.projects.max(by: { $0.totalTokens < $1.totalTokens })?.name ?? "—"
    }

    private func chartHeight(for size: CGSize) -> CGFloat {
        min(130, max(92, size.height * 0.24))
    }

    private var shouldShowClaude: Bool {
        state.claude.state == .connected || settings.showUnavailableProviders
    }

    @ViewBuilder
    private func paceLine(_ insight: PaceInsight) -> some View {
        if let safe = insight.safePercentToday {
            Text(tr(settings.language, "Сегодня безопасно потратить не более \(Int(safe.rounded()))%", "Safe to use today: no more than \(Int(safe.rounded()))%"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text(tr(settings.language, "Собираем данные о темпе", "Learning your usage pace"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func healthTitle(for level: HealthLevel) -> String {
        switch level {
        case .healthy: tr(settings.language, "Темп нормальный", "Pace is healthy")
        case .watch: tr(settings.language, "Расход выше безопасного", "Usage is above budget")
        case .critical: tr(settings.language, "Запас заканчивается", "Quota is running low")
        case .unknown: tr(settings.language, "Собираем данные", "Waiting for data")
        }
    }

    private func healthSymbol(for level: HealthLevel) -> String {
        switch level {
        case .healthy: "checkmark.circle.fill"
        case .watch: "exclamationmark.triangle.fill"
        case .critical: "bolt.trianglebadge.exclamationmark.fill"
        case .unknown: "clock"
        }
    }

    private var activeProvider: ProviderKind {
        resolvedWidgetProvider(selectedProvider, claudeState: state.claude.state)
    }

    private var selectedSnapshot: ProviderSnapshot {
        activeProvider == .codex ? state.codex : state.claude
    }

    private var selectedInsight: PaceInsight? {
        state.pace[activeProvider]
    }

    private var selectedHealthLevel: HealthLevel {
        selectedInsight?.level ?? .unknown
    }

    private var selectedPaceTitle: String {
        activeProvider.displayName + " · " + healthTitle(for: selectedHealthLevel)
    }

    private var selectedResetAt: Date? {
        selectedSnapshot.quota?.resetsAt
            ?? (activeProvider == .codex ? codexWidgetMeters.first : claudeWidgetMeters.first)?.window.resetsAt
    }

    private var widgetSummary: String {
        tr(
            settings.language,
            "\(activeProvider.displayName): осталось \(percentText(selectedSnapshot.remainingPercent)). \(selectedResetText). \(quotaForecastText(selectedInsight, language: settings.language))",
            "\(activeProvider.displayName): \(percentText(selectedSnapshot.remainingPercent)) left. \(selectedResetText). \(quotaForecastText(selectedInsight, language: settings.language))"
        )
    }

    private var selectedResetText: String {
        guard activeProvider == .claude else {
            return weeklyQuotaResetText(selectedResetAt, language: settings.language)
        }
        let scope = state.claudeAccountDetails.quotaMeters.first { $0.window == selectedSnapshot.quota }?.scope
        if scope == .session {
            return sessionQuotaResetText(selectedResetAt, language: settings.language)
        }
        return weeklyQuotaResetText(selectedResetAt, language: settings.language)
    }

    private var widgetProviderSubtitle: String {
        let codexPlan = codexPlanName(state.codexAccountDetails.planType, language: settings.language)
            ?? tr(settings.language, "Codex подключён", "Codex connected")
        guard state.claude.state == .connected else { return codexPlan }
        return codexPlan + " · " + (state.claudeAccountDetails.planName ?? "Claude")
    }
}

func resolvedWidgetProvider(
    _ selected: ProviderKind,
    claudeState: ProviderConnectionState
) -> ProviderKind {
    selected == .claude && claudeState != .connected ? .codex : selected
}

enum WidgetLayout: Equatable {
    case mini
    case compact
    case focus
    case expanded

    static let minimumCompactHeight: CGFloat = 100

    init(size: CGSize) {
        if size.width < 180 || size.height < Self.minimumCompactHeight {
            self = .mini
        } else if size.width < 292 || size.height < 176 {
            self = .compact
        } else if size.width < 380 && size.height < 360 {
            self = .focus
        } else {
            self = .expanded
        }
    }
}

private struct WidgetUsageChart: View {
    let days: [DailyTokenUsage]

    var body: some View {
        Chart(days) { day in
            BarMark(
                x: .value("Date", day.parsedDate ?? .now),
                y: .value("Tokens", day.totalTokens)
            )
            .foregroundStyle(Color.pulseTeal.gradient)
            .cornerRadius(2)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityLabel("Daily Codex token usage")
    }
}
