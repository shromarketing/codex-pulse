import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var codex = ProviderSnapshot.loading(.codex)
    @Published var claude = ProviderSnapshot.loading(.claude)
    @Published var history: [UsagePoint] = []
    @Published var isRefreshing = false
    @Published var lastUpdated: Date?
    @Published var taskText = ""
    @Published var recommendation: RouteRecommendation?

    let settings = SettingsStore.shared
    private let coordinator = ProviderCoordinator()
    private let historyStore = UsageHistoryStore()
    private let router = TaskRouter()

    private init() {}

    var connectedSnapshots: [ProviderSnapshot] {
        [codex, claude].filter { $0.state == .connected }
    }

    var combinedRemaining: Double? {
        let values = connectedSnapshots.compactMap(\.remainingPercent)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var nearestReset: Date? {
        connectedSnapshots.compactMap { $0.quota?.resetsAt }.min()
    }

    var healthLevel: HealthLevel {
        guard let remaining = combinedRemaining else { return .unknown }
        if remaining >= 35 { return .healthy }
        if remaining >= 15 { return .watch }
        return .critical
    }

    func start() {
        Task {
            history = await historyStore.load()
            await refresh()
            syncFloatingPanel()
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        async let codexResult = coordinator.fetchCodex()
        async let claudeResult = coordinator.fetchClaude()
        let results = await (codexResult, claudeResult)
        codex = results.0
        claude = results.1
        history = await historyStore.record([codex, claude])
        lastUpdated = .now
        isRefreshing = false
    }

    func routeCurrentTask() {
        let trimmed = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            recommendation = nil
            return
        }
        recommendation = router.recommend(task: trimmed, codex: codex, claude: claude)
    }

    func syncFloatingPanel() {
        if settings.showFloatingWidget {
            FloatingPanelController.shared.show()
        } else {
            FloatingPanelController.shared.hide()
        }
    }
}

enum HealthLevel {
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
