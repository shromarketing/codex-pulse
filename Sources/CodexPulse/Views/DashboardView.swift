import Charts
import SwiftUI

private enum DashboardSection: String, CaseIterable, Identifiable {
    case overview
    case history
    case router
    case settings
    var id: String { rawValue }
}

@MainActor
private final class DashboardUIState: ObservableObject {
    static let shared = DashboardUIState()

    @Published var section: DashboardSection = .overview
    @Published var showQuickSettings = false
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
                case .overview: overview
                case .history: historyScreen
                case .router: routerScreen
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    ui.showQuickSettings.toggle()
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .popover(isPresented: $ui.showQuickSettings, arrowEdge: .top) {
                    QuickSettingsView()
                        .environmentObject(state)
                        .environmentObject(settings)
                        .frame(width: 360)
                        .padding(18)
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.pulseTeal)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Codex Pulse").font(.headline)
                    Text("v0.1").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 16)

            sidebarButton(.overview, icon: "rectangle.grid.2x2", ru: "Обзор", en: "Overview")
            sidebarButton(.history, icon: "chart.xyaxis.line", ru: "История", en: "History")
            sidebarButton(.router, icon: "point.3.connected.trianglepath.dotted", ru: "Маршрут задачи", en: "Task router")
            sidebarButton(.settings, icon: "gearshape", ru: "Настройки", en: "Settings")

            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Label(tr(settings.language, "Локально и приватно", "Local and private"), systemImage: "lock.shield")
                    .font(.caption.weight(.semibold))
                Text(tr(settings.language, "Не читаем промпты и не сохраняем данные аккаунтов.", "No prompt reading or account data storage."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .pulseSurface()
        }
        .padding(18)
        .frame(width: 210)
    }

    private func sidebarButton(_ item: DashboardSection, icon: String, ru: String, en: String) -> some View {
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

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                HStack(spacing: 14) {
                    ProviderCard(snapshot: state.codex)
                    ProviderCard(snapshot: state.claude)
                    HealthCard()
                        .frame(minWidth: 215)
                }
                UsageHistoryCard()
                TaskRouterCard()
            }
            .padding(22)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tr(settings.language, "Состояние квот", "Quota overview"))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(tr(settings.language, "Codex и Claude в одном спокойном рабочем контуре", "Codex and Claude in one calm workspace"))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state.isRefreshing {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await state.refresh() }
            } label: {
                Label(tr(settings.language, "Обновить", "Refresh"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    private var historyScreen: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(tr(settings.language, "История", "History"))
                .font(.largeTitle.weight(.semibold))
            UsageHistoryCard(expanded: true)
            Spacer()
        }
        .padding(24)
    }

    private var routerScreen: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(tr(settings.language, "Маршрут новой задачи", "Route a new task"))
                .font(.largeTitle.weight(.semibold))
            TaskRouterCard(expanded: true)
            Spacer()
        }
        .padding(24)
    }
}

private struct ProviderCard: View {
    @EnvironmentObject private var settings: SettingsStore
    let snapshot: ProviderSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label {
                    Text(snapshot.provider.displayName).font(.title3.weight(.semibold))
                } icon: {
                    Image(systemName: snapshot.provider.symbol)
                        .foregroundStyle(snapshot.provider.tint)
                }
                Spacer()
                Circle()
                    .fill(snapshot.state == .connected ? Color.pulseGreen : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(statusTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let remaining = snapshot.remainingPercent {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 10)
                        Circle()
                            .trim(from: 0, to: remaining / 100)
                            .stroke(snapshot.provider.tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text(percentText(remaining)).font(.system(size: 26, weight: .medium, design: .monospaced))
                            Text(tr(settings.language, "осталось", "left")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 112, height: 112)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(tr(settings.language, "Сброс", "Reset"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(resetText(snapshot.quota?.resetsAt, language: settings.language))
                            .font(.headline.monospacedDigit())
                        if let date = snapshot.quota?.resetsAt {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(snapshot.source)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr(settings.language, "Не подключён", "Not connected"))
                        .font(.title3.weight(.medium))
                    Text(localizedMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Text(tr(settings.language, "Подключите сервис локально — Pulse не запрашивает пароль.", "Connect the provider locally — Pulse never asks for your password."))
                        .font(.caption2)
                        .foregroundStyle(snapshot.provider.tint)
                }
                .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .pulseSurface()
    }

    private var statusTitle: String {
        switch snapshot.state {
        case .connected: tr(settings.language, "Активно", "Active")
        case .loading: tr(settings.language, "Загрузка", "Loading")
        case .unavailable: tr(settings.language, "Нет связи", "Offline")
        case .error: tr(settings.language, "Ошибка", "Error")
        }
    }

    private var localizedMessage: String {
        guard let message = snapshot.message else { return tr(settings.language, "Нет данных", "No data") }
        if snapshot.provider == .claude {
            return tr(settings.language, "Сессия Claude пока не найдена.", "No Claude session was found yet.")
        }
        return message
    }
}

private struct HealthCard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(tr(settings.language, "Общее состояние", "Overall health"), systemImage: "heart.text.square")
                .font(.headline)
            Text(healthTitle)
                .font(.title2.weight(.semibold))
                .foregroundStyle(state.healthLevel.color)
            Text(healthExplanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let value = state.combinedRemaining {
                Text(percentText(value))
                    .font(.system(size: 30, weight: .medium, design: .monospaced))
                Text(tr(settings.language, "средний доступный запас", "average quota remaining"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .pulseSurface()
    }

    private var healthTitle: String {
        switch state.healthLevel {
        case .healthy: tr(settings.language, "Темп нормальный", "Pace is healthy")
        case .watch: tr(settings.language, "Стоит следить", "Keep an eye on it")
        case .critical: tr(settings.language, "Запас заканчивается", "Quota is running low")
        case .unknown: tr(settings.language, "Нужны данные", "Waiting for data")
        }
    }

    private var healthExplanation: String {
        switch state.healthLevel {
        case .healthy: tr(settings.language, "Можно продолжать работу и выбирать сервис под задачу.", "You can keep working and choose the best provider for each task.")
        case .watch: tr(settings.language, "Для сложной задачи сначала проверьте маршрут и время сброса.", "Check the route and reset time before a large task.")
        case .critical: tr(settings.language, "Большую задачу лучше разбить или перенести после сброса.", "Split a large task or wait until the next reset.")
        case .unknown: tr(settings.language, "Подключите хотя бы один сервис.", "Connect at least one provider.")
        }
    }
}

private struct UsageHistoryCard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore
    var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tr(settings.language, "Расход за последние дни", "Recent usage"))
                    .font(.headline)
                Spacer()
                Text(tr(settings.language, "Локальная история", "Local history"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if state.history.count >= 2 {
                Chart(state.history) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Used", point.usedPercent),
                        series: .value("Provider", point.provider.rawValue)
                    )
                    .foregroundStyle(by: .value("Provider", point.provider.rawValue))
                    .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", point.date), y: .value("Used", point.usedPercent))
                        .foregroundStyle(point.provider.tint)
                }
                .chartForegroundStyleScale([
                    ProviderKind.codex.rawValue: Color.pulseTeal,
                    ProviderKind.claude.rawValue: Color.pulseOrange,
                ])
                .chartYScale(domain: 0 ... 100)
                .frame(height: expanded ? 360 : 150)
            } else {
                VStack(spacing: 9) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(tr(settings.language, "История собирается", "Building local history"))
                        .font(.headline)
                    Text(tr(settings.language, "Pulse сохраняет только проценты лимита на этом Mac.", "Pulse stores quota percentages only on this Mac."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: expanded ? 320 : 130)
            }
        }
        .padding(16)
        .pulseSurface()
    }
}

private struct TaskRouterCard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore
    var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr(settings.language, "Рекомендация для задачи", "Task recommendation"))
                .font(.headline)
            HStack(alignment: .top, spacing: 12) {
                TextField(
                    tr(settings.language, "Опишите задачу…", "Describe the task…"),
                    text: $state.taskText,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(expanded ? 4 : 2)
                .onSubmit { state.routeCurrentTask() }

                Button {
                    state.routeCurrentTask()
                } label: {
                    Label(tr(settings.language, "Подобрать модель", "Choose model"), systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.pulseTeal)
                .disabled(state.taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let recommendation = state.recommendation {
                Divider()
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(recommendation.model.rawValue) · \(recommendation.effort.rawValue)")
                            .font(.title2.weight(.semibold))
                        Text(L10n.estimateTitle(recommendation.estimate, language: settings.language))
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr(settings.language, "Лучше запустить в \(recommendation.provider.displayName)", "Best run in \(recommendation.provider.displayName)"))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(recommendation.provider.tint)
                        Text(settings.language == .russian ? recommendation.rationaleRU : recommendation.rationaleEN)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(tr(settings.language, "Рекомендация, не автозапуск", "Recommendation only"), systemImage: "hand.raised")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .pulseSurface()
    }
}
