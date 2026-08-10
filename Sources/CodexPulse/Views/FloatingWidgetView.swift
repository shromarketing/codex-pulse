import SwiftUI

struct FloatingWidgetView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "waveform.path.ecg").foregroundStyle(Color.pulseTeal)
                Text("Codex Pulse").font(.headline)
                Spacer()
                Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary)
                Button {
                    settings.showFloatingWidget = false
                    state.syncFloatingPanel()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            .padding(14)

            Divider().opacity(0.55)

            HStack(spacing: 0) {
                widgetProvider(state.codex)
                Divider().frame(height: 82)
                widgetProvider(state.claude)
            }
            .padding(.vertical, 16)

            Divider().opacity(0.55)

            VStack(spacing: 8) {
                Text(tr(settings.language, "Ближайший сброс", "Nearest reset"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(resetText(state.nearestReset, language: settings.language))
                    .font(.title3.monospacedDigit().weight(.medium))
                Label(healthTitle, systemImage: "heart.text.square")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(state.healthLevel.color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(state.healthLevel.color.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(16)

            Spacer(minLength: 8)

            Button {
                Task { await state.refresh() }
            } label: {
                Label(tr(settings.language, "Обновить", "Refresh"), systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(12)
        }
        .frame(width: 270, height: 330)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .preferredColorScheme(settings.theme.colorScheme)
    }

    private func widgetProvider(_ snapshot: ProviderSnapshot) -> some View {
        VStack(spacing: 7) {
            Label(snapshot.provider.displayName, systemImage: snapshot.provider.symbol)
                .foregroundStyle(snapshot.provider.tint)
                .font(.callout.weight(.medium))
            Text(percentText(snapshot.remainingPercent))
                .font(.system(size: 29, weight: .medium, design: .monospaced))
            Text(tr(settings.language, "осталось", "left"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var healthTitle: String {
        switch state.healthLevel {
        case .healthy: tr(settings.language, "Темп нормальный", "Pace is healthy")
        case .watch: tr(settings.language, "Следите за запасом", "Watch your quota")
        case .critical: tr(settings.language, "Низкий запас", "Quota is low")
        case .unknown: tr(settings.language, "Нет данных", "No data")
        }
    }
}
