import Foundation
import SwiftUI

func tr(_ language: AppLanguage, _ ru: String, _ en: String) -> String {
    L10n.text(language, ru: ru, en: en)
}

func percentText(_ value: Double?) -> String {
    guard let value else { return "—" }
    return "\(Int(value.rounded()))%"
}

func compactTokens(_ value: Int64) -> String {
    let number = Double(value)
    if number >= 1_000_000_000 { return String(format: "%.1fB", number / 1_000_000_000) }
    if number >= 1_000_000 { return String(format: "%.1fM", number / 1_000_000) }
    if number >= 1_000 { return String(format: "%.1fK", number / 1_000) }
    return "\(value)"
}

func currency(_ value: Double, code: String = "USD", language: AppLanguage) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = code
    formatter.locale = language.locale
    formatter.maximumFractionDigits = value >= 100 ? 0 : 2
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
}

func localizedDate(
    _ value: Date,
    language: AppLanguage,
    dateStyle: DateFormatter.Style,
    timeStyle: DateFormatter.Style
) -> String {
    let formatter = DateFormatter()
    formatter.locale = language.locale
    formatter.dateStyle = dateStyle
    formatter.timeStyle = timeStyle
    return formatter.string(from: value)
}

func compactDuration(_ seconds: Int64, language: AppLanguage) -> String {
    let minutes = seconds / 60
    if minutes < 60 { return tr(language, "\(minutes) мин", "\(minutes)m") }
    let hours = minutes / 60
    let remainder = minutes % 60
    return tr(language, "\(hours) ч \(remainder) мин", "\(hours)h \(remainder)m")
}

func resetText(_ date: Date?, language: AppLanguage, now: Date = .now) -> String {
    guard let date else { return tr(language, "Нет данных", "No data") }
    let interval = max(0, date.timeIntervalSince(now))
    let days = Int(interval) / 86_400
    let hours = (Int(interval) % 86_400) / 3_600
    let minutes = (Int(interval) % 3_600) / 60
    if days > 0 { return tr(language, "через \(days) д \(hours) ч", "in \(days)d \(hours)h") }
    if hours > 0 { return tr(language, "через \(hours) ч \(minutes) мин", "in \(hours)h \(minutes)m") }
    return tr(language, "через \(minutes) мин", "in \(minutes)m")
}

func quotaResetText(_ date: Date?, language: AppLanguage, now: Date = .now, compact: Bool = false) -> String {
    guard date != nil else { return tr(language, "Время сброса неизвестно", "Reset time unavailable") }
    let duration = resetText(date, language: language, now: now)
    if compact {
        return tr(language, "Сброс \(duration)", "Resets \(duration)")
    }
    return tr(language, "Лимит обновится \(duration)", "Limit resets \(duration)")
}

func weeklyQuotaResetText(_ date: Date?, language: AppLanguage, now: Date = .now) -> String {
    guard date != nil else {
        return tr(language, "Время обновления недели уточняется", "Weekly reset time is unavailable")
    }
    let duration = resetText(date, language: language, now: now)
    return tr(
        language,
        "Недельный лимит обновится \(duration)",
        "Weekly limit resets \(duration)"
    )
}

func sessionQuotaResetText(_ date: Date?, language: AppLanguage, now: Date = .now) -> String {
    guard date != nil else {
        return tr(language, "Время обновления сессии уточняется", "Session reset time is unavailable")
    }
    let duration = resetText(date, language: language, now: now)
    return tr(
        language,
        "Лимит сессии обновится \(duration)",
        "Session limit resets \(duration)"
    )
}

func quotaForecastText(
    _ insight: PaceInsight?,
    language: AppLanguage,
    now: Date = .now,
    compact: Bool = false
) -> String {
    guard let insight else {
        return tr(language, "Прогноз появится после нескольких обновлений", "Forecast appears after a few updates")
    }
    if let exhaustion = insight.projectedExhaustion,
       let reset = insight.resetAt {
        if exhaustion < reset {
            let duration = resetText(exhaustion, language: language, now: now)
            return compact
                ? tr(language, "Закончится \(duration)", "Runs out \(duration)")
                : tr(language, "При текущем темпе закончится \(duration)", "At this pace, quota runs out \(duration)")
        }
        return compact
            ? tr(language, "Хватит до сброса", "Lasts until reset")
            : tr(language, "Запаса должно хватить до обновления лимита", "Quota should last until the limit resets")
    }
    return compact
        ? tr(language, "Прогноз уточняется", "Forecast pending")
        : tr(language, "Прогноз появится после нескольких обновлений", "Forecast appears after a few updates")
}

struct QuotaMeterItem: Identifiable {
    let id: String
    let title: String
    let window: QuotaWindow
    let scope: ClaudeQuotaScope?

    init(id: String, title: String, window: QuotaWindow, scope: ClaudeQuotaScope? = nil) {
        self.id = id
        self.title = title
        self.window = window
        self.scope = scope
    }
}

func codexQuotaMeters(_ details: CodexAccountDetails, language: AppLanguage) -> [QuotaMeterItem] {
    details.quotaBuckets.flatMap { bucket -> [QuotaMeterItem] in
        let name = quotaBucketName(bucket)
        var values: [QuotaMeterItem] = []
        if let secondary = bucket.secondary {
            values.append(QuotaMeterItem(
                id: bucket.id + "-secondary",
                title: name + " · " + quotaWindowName(secondary.windowMinutes, language: language),
                window: secondary
            ))
        }
        if let primary = bucket.primary {
            values.append(QuotaMeterItem(
                id: bucket.id + "-primary",
                title: name + " · " + quotaWindowName(primary.windowMinutes, language: language),
                window: primary
            ))
        }
        return values
    }
}

func claudeQuotaMeters(
    _ details: ClaudeAccountDetails,
    language: AppLanguage,
    includeProvider: Bool = false
) -> [QuotaMeterItem] {
    details.quotaMeters.filter(\.usageKnown).map { meter in
        let coreTitle: String = switch meter.scope {
        case .session:
            tr(language, "Текущая сессия", "Current session")
        case .weekly:
            tr(language, "Все модели · неделя", "All models · week")
        case .modelWeekly:
            meter.providerTitle.map { $0 + tr(language, " · неделя", " · week") }
                ?? tr(language, "Модель · неделя", "Model · week")
        }
        let title = includeProvider ? "Claude · " + coreTitle : coreTitle
        return QuotaMeterItem(id: meter.id, title: title, window: meter.window, scope: meter.scope)
    }
}

func claudeMeterResetText(_ meter: QuotaMeterItem, language: AppLanguage) -> String {
    guard meter.window.resetsAt != nil else {
        return tr(
            language,
            "Время следующего сброса пока не передано",
            "Next reset time is not available yet"
        )
    }
    return meter.scope == .session
        ? sessionQuotaResetText(meter.window.resetsAt, language: language)
        : weeklyQuotaResetText(meter.window.resetsAt, language: language)
}

func quotaUsageText(_ window: QuotaWindow, language: AppLanguage) -> String {
    tr(
        language,
        "Использовано \(percentText(window.usedPercent))",
        "\(percentText(window.usedPercent)) used"
    )
}

struct ClaudeQuotaMeterView: View {
    let meter: QuotaMeterItem
    let language: AppLanguage
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(meter.title)
                    .font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(percentText(meter.window.remainingPercent))
                    .font(compact ? .callout.monospacedDigit().weight(.semibold) : .headline.monospacedDigit())
                Text(tr(language, "осталось", "left"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: meter.window.remainingPercent, total: 100)
                .tint(Color.pulseOrange)
                .accessibilityLabel(tr(
                    language,
                    "Осталось \(percentText(meter.window.remainingPercent)). \(quotaUsageText(meter.window, language: language)). \(claudeMeterResetText(meter, language: language))",
                    "\(percentText(meter.window.remainingPercent)) left. \(quotaUsageText(meter.window, language: language)). \(claudeMeterResetText(meter, language: language))"
                ))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(quotaUsageText(meter.window, language: language))
                Spacer(minLength: 8)
                Text(claudeMeterResetText(meter, language: language))
                    .multilineTextAlignment(.trailing)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

func claudeUsageSourceTitle(_ source: ClaudeUsageSource, language: AppLanguage) -> String {
    switch source {
    case .off: tr(language, "Отключено", "Off")
    case .browserExtension: tr(language, "Pulse Connector (рекомендуется)", "Pulse Connector (recommended)")
    case .web: tr(language, "CodexBar · Chrome (legacy)", "CodexBar · Chrome (legacy)")
    case .oauth: "OAuth"
    case .automatic: tr(language, "Автоматически", "Automatic")
    }
}

func codexPlanName(_ raw: String?, language: AppLanguage) -> String? {
    guard let raw else { return nil }
    switch raw {
    case "self_serve_business_prolite", "self_serve_business_usage_based", "business":
        return tr(language, "ChatGPT Business", "ChatGPT Business")
    case "team": return "ChatGPT Team"
    case "pro", "prolite": return "ChatGPT Pro"
    case "plus": return "ChatGPT Plus"
    case "enterprise", "enterprise_cbp_automation", "enterprise_cbp_usage_based", "ent26": return "ChatGPT Enterprise"
    case "edu": return "ChatGPT Edu"
    case "free": return tr(language, "Бесплатный план", "Free plan")
    case "go": return "ChatGPT Go"
    default: return nil
    }
}

private func quotaBucketName(_ bucket: CodexQuotaBucket) -> String {
    if let name = bucket.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
        if name.lowercased().contains("codex") && name.lowercased().contains("spark") { return "Codex Spark" }
        return name
    }
    if bucket.id.lowercased().contains("spark") { return "Codex Spark" }
    if bucket.id.lowercased() == "codex" { return "Codex" }
    return bucket.id
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")
        .split(separator: " ")
        .map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
        .joined(separator: " ")
}

func quotaWindowName(_ minutes: Int?, language: AppLanguage) -> String {
    guard let minutes else { return tr(language, "лимит", "limit") }
    if minutes >= 10_080 { return tr(language, "неделя", "week") }
    if minutes >= 1_440 {
        let days = max(1, minutes / 1_440)
        return tr(language, "\(days) дн.", "\(days)d")
    }
    if minutes >= 60 {
        let hours = max(1, minutes / 60)
        return tr(language, "\(hours) ч", "\(hours)h")
    }
    return tr(language, "\(minutes) мин", "\(minutes)m")
}

struct PulseSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

extension View {
    func pulseSurface() -> some View { modifier(PulseSurfaceModifier()) }
}
