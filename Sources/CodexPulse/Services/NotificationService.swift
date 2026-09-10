import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let defaults = UserDefaults.standard

    private init() {}

    func requestPermission() async -> Bool {
        (try? await Self.requestAuthorization()) ?? false
    }

    func evaluate(
        provider: ProviderSnapshot,
        insight: PaceInsight,
        settings: SettingsStore
    ) async {
        guard settings.notificationsEnabled,
              let remaining = provider.remainingPercent
        else { return }

        let key = "notification.band.\(provider.provider.rawValue)"
        let previousBand = defaults.string(forKey: key)
        let band: String
        let title: String
        let body: String

        if remaining <= Double(settings.criticalThreshold) {
            band = "critical"
            title = tr(settings.language, "\(provider.provider.displayName): лимит почти исчерпан", "\(provider.provider.displayName): quota is almost gone")
            body = tr(settings.language, "Осталось \(Int(remaining.rounded()))%. Большую задачу лучше перенести или разбить.", "\(Int(remaining.rounded()))% remains. Consider splitting or postponing a large task.")
        } else if remaining <= Double(settings.warningThreshold) {
            band = "warning"
            title = tr(settings.language, "\(provider.provider.displayName): расход высокий", "\(provider.provider.displayName): usage is high")
            body = tr(settings.language, "Осталось \(Int(remaining.rounded()))% до сброса.", "\(Int(remaining.rounded()))% remains until reset.")
        } else if settings.predictiveAlerts,
                  let exhaustion = insight.projectedExhaustion,
                  let reset = insight.resetAt,
                  exhaustion < reset {
            band = "pace"
            title = tr(settings.language, "\(provider.provider.displayName): темп выше безопасного", "\(provider.provider.displayName): pace is above budget")
            body = tr(settings.language, "При текущем темпе запас может закончиться до сброса.", "At the current pace, quota may run out before reset.")
        } else {
            band = "healthy"
            if previousBand == "critical" || previousBand == "warning" {
                await deliver(
                    id: "\(provider.provider.rawValue)-restored",
                    title: tr(settings.language, "\(provider.provider.displayName): квота восстановлена", "\(provider.provider.displayName): quota restored"),
                    body: tr(settings.language, "Снова доступно \(Int(remaining.rounded()))%.", "\(Int(remaining.rounded()))% is available again."),
                    sound: settings.notificationSound
                )
            }
            defaults.set(band, forKey: key)
            return
        }

        guard previousBand != band else { return }
        defaults.set(band, forKey: key)
        await deliver(
            id: "\(provider.provider.rawValue)-\(band)",
            title: title,
            body: body,
            sound: settings.notificationSound
        )
    }

    func notify(resetSignal: ResetSignal, settings: SettingsStore) async {
        guard settings.notificationsEnabled else { return }

        let title: String
        let kind: String
        switch resetSignal.kind {
        case .usageReset:
            title = tr(settings.language, "\(resetSignal.provider.displayName): анонсирован сброс лимита", "\(resetSignal.provider.displayName): usage reset announced")
            kind = tr(settings.language, "сброс лимита", "usage reset")
        case .bankedReset:
            title = tr(settings.language, "\(resetSignal.provider.displayName): анонсирован banked reset", "\(resetSignal.provider.displayName): banked reset announced")
            kind = "banked reset"
        case .quotaExpansion:
            title = tr(settings.language, "Claude: временно расширен лимит", "Claude: quota temporarily expanded")
            kind = tr(settings.language, "временное расширение лимита", "temporary quota expansion")
        }
        let timing = resetSignal.timingHint.map { timingText($0, language: settings.language) }
            ?? tr(settings.language, "срок не указан", "timing was not specified")
        let timingDescription: String
        if let estimatedResetAt = resetSignal.estimatedResetAt {
            timingDescription = tr(
                settings.language,
                "ориентировочно \(moscowTime(estimatedResetAt, language: settings.language)) по времени публикации",
                "estimated \(moscowTime(estimatedResetAt, language: settings.language)) from the post time"
            )
        } else {
            timingDescription = timing
        }
        let body = tr(
            settings.language,
            "\(sourceName(resetSignal, language: settings.language)) сообщил про \(kind): \(timingDescription). Условия могут зависеть от тарифа; откройте первоисточник в Pulse.",
            "\(sourceName(resetSignal, language: settings.language)) reported a \(kind): \(timingDescription). Eligibility may depend on your plan; open the original source in Pulse."
        )
        await deliver(
            id: "reset-signal.\(resetSignal.id)",
            title: title,
            body: body,
            sound: settings.notificationSound,
            sourceURL: resetSignal.sourceURL
        )
    }

    func sendSignalTest(settings: SettingsStore) async -> Bool {
        guard settings.notificationsEnabled,
              await requestPermission()
        else { return false }
        await deliver(
            id: "reset-signal.test.\(UUID().uuidString)",
            title: tr(settings.language, "Codex Pulse: тест уведомления", "Codex Pulse: notification test"),
            body: tr(settings.language, "Уведомления о новых анонсах сброса будут приходить сюда.", "New reset-announcement alerts will arrive here."),
            sound: settings.notificationSound
        )
        return true
    }

    private func deliver(id: String, title: String, body: String, sound: Bool, sourceURL: URL? = nil) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        if let sourceURL { content.userInfo = ["resetSignalURL": sourceURL.absoluteString] }
        try? await Self.addNotification(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    private func timingText(_ hint: String, language: AppLanguage) -> String {
        switch hint {
        case "end of day": return tr(language, "до конца дня", "by end of day")
        case "next hour": return tr(language, "в ближайший час", "within the next hour")
        case "today": return tr(language, "сегодня", "today")
        default: return hint
        }
    }

    private func sourceName(_ signal: ResetSignal, language: AppLanguage) -> String {
        switch signal.source {
        case .tibo: return "Tibo из OpenAI"
        case .claudeStatus: return tr(language, "официальный статус Claude", "Claude's official status")
        }
    }

    private func moscowTime(_ date: Date, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.timeZone = TimeZone(identifier: "Europe/Moscow")
        formatter.setLocalizedDateFormatFromTemplate("dMMM HH:mm")
        return formatter.string(from: date) + (language == .russian ? " МСК" : " MSK")
    }

    private nonisolated static func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    private nonisolated static func addNotification(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }
}
