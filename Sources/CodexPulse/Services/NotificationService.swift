import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    private init() {}

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
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

    private func deliver(id: String, title: String, body: String, sound: Bool) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
