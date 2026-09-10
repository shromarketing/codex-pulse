import SwiftUI

struct ResetSignalCard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore
    @State private var notificationTestMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(tr(settings.language, "Сигналы лимитов", "Quota signals"), systemImage: "bell.badge")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.pulseTeal)
                Spacer()
                statusLabel
            }

            signalSection(
                title: tr(settings.language, "Codex", "Codex"),
                provider: .codex,
                tint: Color.pulseTeal,
                status: state.resetSignalStatus,
                confirmation: AnyView(codexAccountConfirmation)
            )

            Divider().opacity(0.5)

            signalSection(
                title: tr(settings.language, "Claude · Web, Desktop и Code", "Claude · Web, Desktop, and Code"),
                provider: .claude,
                tint: ProviderKind.claude.tint,
                status: state.claudeResetSignalStatus,
                confirmation: AnyView(claudeAccountConfirmation)
            )

            Button {
                Task { await state.refreshResetSignals() }
            } label: {
                HStack(spacing: 6) {
                    if state.isCheckingResetSignals {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "bell.and.waves.left.and.right")
                    }
                    Text(state.isCheckingResetSignals
                         ? tr(settings.language, "Проверяем сигналы…", "Checking signals…")
                         : tr(settings.language, "Проверить сигналы", "Check signals"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.pulseTeal)
            .disabled(state.isCheckingResetSignals || !settings.resetSignalChecksEnabled)

            notificationTest

            Text(sourceNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }

    private var statusLabel: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(combinedStatusText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(statusColor)
            if let checkedAt = [state.resetSignalStatus.checkedAt, state.claudeResetSignalStatus.checkedAt].compactMap({ $0 }).max() {
                Text(localizedDate(checkedAt, language: settings.language, dateStyle: .none, timeStyle: .short))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func signalSection(
        title: String,
        provider: ProviderKind,
        tint: Color,
        status: ResetSignalMonitorStatus,
        confirmation: AnyView
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "bell")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            if let signal = status.recentSignals.first ?? status.latestSignal {
                signalContent(signal)
                recentSignalHistory(status)
            } else {
                Text(emptyMessage(for: status, provider: provider))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            confirmation
        }
    }

    private func signalContent(_ signal: ResetSignal) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(signalTitle(signal.kind))
                .font(.caption.weight(.semibold))
            Text(timingText(signal))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(russianSummary(for: signal))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let publishedAt = signal.publishedAt {
                Text(tr(settings.language, "Пост опубликован: ", "Post published: ") + moscowDate(publishedAt))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Link(destination: signal.sourceURL) {
                Label(linkTitle(for: signal), systemImage: "arrow.up.right.square")
                    .font(.caption.weight(.medium))
            }
        }
    }

    @ViewBuilder
    private func recentSignalHistory(_ status: ResetSignalMonitorStatus) -> some View {
        let previous = Array(status.recentSignals.dropFirst())
        if !previous.isEmpty {
            Divider().opacity(0.5)
            Text(tr(settings.language, "Недавние релевантные анонсы", "Recent relevant announcements"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(previous) { signal in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(signalTitle(signal.kind))
                            .font(.caption2.weight(.medium))
                        Text(russianSummary(for: signal))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if let publishedAt = signal.publishedAt {
                        Text(moscowDate(publishedAt))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }

    private var codexAccountConfirmation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(tr(settings.language, "Подтверждение в вашем Codex", "Confirmation in your Codex"), systemImage: "checkmark.seal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.pulseGreen)
            if state.codexAccountDetails.resetCreditsAvailable > 0 {
                Text(tr(
                    settings.language,
                    "App Server видит доступных сохранённых сбросов: \(state.codexAccountDetails.resetCreditsAvailable). Это подтверждает состояние именно вашего аккаунта.",
                    "App Server sees \(state.codexAccountDetails.resetCreditsAvailable) available banked resets in this account."
                ))
            } else {
                Text(tr(
                    settings.language,
                    "App Server пока не видит доступных сохранённых сбросов в этом аккаунте. Ранний анонс может появиться раньше подтверждения.",
                    "App Server does not currently see an available banked reset in this account. An early announcement can arrive before confirmation."
                ))
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var claudeAccountConfirmation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(tr(settings.language, "Подтверждение в вашем Claude", "Confirmation in your Claude"), systemImage: "checkmark.seal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(state.claude.state == .connected ? Color.pulseGreen : .secondary)
            if state.claude.state == .connected, let quota = state.claude.quota {
                Text(tr(
                    settings.language,
                    "Pulse Connector подтверждает текущую квоту: осталось \(Int(quota.remainingPercent.rounded()))%. Web, Desktop и Code используют этот общий лимит.",
                    "Pulse Connector confirms the current quota: \(Int(quota.remainingPercent.rounded()))% remains. Web, Desktop, and Code share this limit."
                ))
            } else {
                Text(tr(
                    settings.language,
                    "Claude Web пока не передал живую квоту. Откройте claude.ai в связанном профиле Chrome и нажмите «Обновить» в расширении — это подтвердит сигнал именно для вашего аккаунта.",
                    "Claude Web has not sent a live quota yet. Open claude.ai in the paired Chrome profile and use Refresh in the extension to confirm the signal for your account."
                ))
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var notificationTest: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                Task {
                    let delivered = await NotificationService.shared.sendSignalTest(settings: settings)
                    notificationTestMessage = delivered
                        ? tr(settings.language, "Тест отправлен в Центр уведомлений macOS.", "A test was sent to macOS Notification Center.")
                        : tr(settings.language, "macOS не разрешила уведомления. Нажмите «Разрешить системные уведомления» в Настройках Pulse.", "macOS notifications are not allowed. Use Allow system notifications in Pulse Settings.")
                }
            } label: {
                Label(tr(settings.language, "Проверить push-уведомление", "Test push notification"), systemImage: "bell.and.waves.left.and.right")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            if let notificationTestMessage {
                Text(notificationTestMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func emptyMessage(for status: ResetSignalMonitorStatus, provider: ProviderKind) -> String {
        switch status.state {
        case .disabled:
            return tr(settings.language, "Мониторинг выключен. Включите его в Настройках, чтобы получать уведомления.", "Monitoring is off. Enable it in Settings to receive notifications.")
        case .unavailable:
            return tr(settings.language, "Источник временно недоступен. Последняя успешная проверка сохранится здесь.", "The source is temporarily unavailable. The last successful check will remain here.")
        case .idle:
            return tr(settings.language, "Пока нет проверки. Нажмите кнопку ниже, чтобы запросить сигналы сейчас.", "No check yet. Use the button below to request signals now.")
        case .checked, .signal:
            return provider == .claude
                ? tr(settings.language, "Официальный статус Claude не публиковал явного анонса сброса или расширения лимита.", "Claude's official status has not published an explicit reset or quota-expansion announcement.")
                : tr(settings.language, "Новых анонсов сброса пока нет.", "There are no new reset announcements yet.")
        }
    }

    private var combinedStatusText: String {
        let states = [state.resetSignalStatus.state, state.claudeResetSignalStatus.state]
        if states.contains(.signal) { return tr(settings.language, "Новый сигнал", "New signal") }
        if states.contains(.unavailable) { return tr(settings.language, "Часть источников недоступна", "Some sources unavailable") }
        if states.contains(.disabled) { return tr(settings.language, "Выключено", "Off") }
        if states.contains(.idle) { return tr(settings.language, "Ожидает проверки", "Waiting to check") }
        return tr(settings.language, "Новых нет", "No new signals")
    }

    private var statusColor: Color {
        let states = [state.resetSignalStatus.state, state.claudeResetSignalStatus.state]
        if states.contains(.signal) { return .pulseGreen }
        if states.contains(.unavailable) { return .orange }
        if states.contains(.disabled) { return .secondary }
        return .secondary
    }

    private func linkTitle(for signal: ResetSignal) -> String {
        switch signal.source {
        case .tibo:
            return tr(settings.language, "Открыть пост Tibo", "Open Tibo post")
        case .claudeStatus:
            return tr(settings.language, "Открыть официальный статус Claude", "Open Claude official status")
        }
    }

    private func signalTitle(_ kind: ResetSignalKind) -> String {
        switch kind {
        case .usageReset: tr(settings.language, "Анонс сброса лимита", "Quota reset announcement")
        case .bankedReset: tr(settings.language, "Анонс сохранённого сброса", "Banked reset announcement")
        case .quotaExpansion: tr(settings.language, "Временное расширение лимита", "Temporary quota expansion")
        }
    }

    private func timingText(_ signal: ResetSignal) -> String {
        if let estimatedAt = signal.estimatedResetAt {
            return tr(
                settings.language,
                "Ориентировочно в Москве: \(moscowDate(estimatedAt)) (расчёт по времени публикации)",
                "Estimated in Moscow: \(moscowDate(estimatedAt)) (calculated from post time)"
            )
        }
        let value: String
        switch signal.timingHint {
        case "end of day":
            return tr(settings.language, "Срок: до конца дня. Точный час и часовой пояс в посте не указаны.", "Timing: by end of day. The post does not state an exact time zone or hour.")
        case "next hour": value = tr(settings.language, "в течение часа", "within the next hour")
        case "today": value = tr(settings.language, "сегодня", "today")
        case let hint?: value = hint
        case nil: value = tr(settings.language, "время в источнике не указано", "the source states no time")
        }
        return tr(settings.language, "Ориентир: \(value)", "Timing: \(value)")
    }

    private func russianSummary(for signal: ResetSignal) -> String {
        resetSignalSummary(signal, language: settings.language)
    }

    private func moscowDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = settings.language.locale
        formatter.timeZone = TimeZone(identifier: "Europe/Moscow")
        formatter.setLocalizedDateFormatFromTemplate("dMMM HH:mm")
        let zone = settings.language == .russian ? "МСК" : "MSK"
        return formatter.string(from: date) + " " + zone
    }

    private var sourceNote: String {
        tr(
            settings.language,
            "Codex: публичная лента Tibo — ранний сигнал. Claude: официальный Statuspage, но показываются только явные сообщения о reset/usage/limit. Любой анонс сверяйте с квотой своего аккаунта.",
            "Codex: Tibo's public feed is an early signal. Claude: the official Statuspage, filtered to explicit reset/usage/limit messages. Verify any announcement against your account quota."
        )
    }

}
