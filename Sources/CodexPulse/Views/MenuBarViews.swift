import AppKit
import SwiftUI

struct MenuBarLabelView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        switch settings.menuBarStyle {
        case .pulse:
            Image(systemName: "waveform.path.ecg")
        case .percentage:
            HStack(spacing: 4) {
                Image(systemName: "waveform.path.ecg")
                Text(percentText(state.combinedRemaining))
            }
        case .dual:
            HStack(spacing: 4) {
                Text("C \(compact(state.codex.remainingPercent))")
                Text("·")
                Text("A \(compact(state.claude.remainingPercent))")
            }
        }
    }

    private func compact(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))%"
    }
}

struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "waveform.path.ecg").foregroundStyle(Color.pulseTeal)
                Text("Codex Pulse").font(.headline)
                Spacer()
                if state.isRefreshing { ProgressView().controlSize(.mini) }
            }

            menuProvider(state.codex)
            menuProvider(state.claude)

            HStack {
                Circle().fill(state.healthLevel.color).frame(width: 8, height: 8)
                Text(healthTitle).font(.callout.weight(.medium))
            }

            Divider()

            HStack {
                Button(tr(settings.language, "Открыть", "Open")) {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openWindow(id: "dashboard")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.pulseTeal)
                Button(tr(settings.language, "Виджет", "Widget")) {
                    settings.showFloatingWidget = true
                    FloatingPanelController.shared.toggle()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button {
                    Task { await state.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 330)
    }

    private func menuProvider(_ snapshot: ProviderSnapshot) -> some View {
        VStack(spacing: 6) {
            HStack {
                Label(snapshot.provider.displayName, systemImage: snapshot.provider.symbol)
                    .foregroundStyle(snapshot.provider.tint)
                Spacer()
                Text(percentText(snapshot.remainingPercent)).font(.headline.monospacedDigit())
            }
            ProgressView(value: snapshot.remainingPercent ?? 0, total: 100)
                .tint(snapshot.provider.tint)
        }
    }

    private var healthTitle: String {
        switch state.healthLevel {
        case .healthy: tr(settings.language, "Темп нормальный", "Pace is healthy")
        case .watch: tr(settings.language, "Следите за запасом", "Watch your quota")
        case .critical: tr(settings.language, "Низкий запас", "Quota is low")
        case .unknown: tr(settings.language, "Подключите сервис", "Connect a provider")
        }
    }
}
