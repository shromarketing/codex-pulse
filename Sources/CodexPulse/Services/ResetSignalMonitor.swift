import Foundation

enum ResetSignalKind: String, Codable, Sendable {
    case usageReset
    case bankedReset
    case quotaExpansion
}

enum ResetSignalSource: String, Codable, Sendable {
    case tibo
    case claudeStatus
}

struct ResetSignal: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let kind: ResetSignalKind
    let sourceURL: URL
    let publishedAt: Date?
    let timingHint: String?
    let estimatedResetAt: Date?
    var summary: String? = nil
    var provider: ProviderKind = .codex
    var source: ResetSignalSource = .tibo

    init(
        id: String,
        kind: ResetSignalKind,
        sourceURL: URL,
        publishedAt: Date?,
        timingHint: String?,
        estimatedResetAt: Date?,
        summary: String? = nil,
        provider: ProviderKind = .codex,
        source: ResetSignalSource = .tibo
    ) {
        self.id = id
        self.kind = kind
        self.sourceURL = sourceURL
        self.publishedAt = publishedAt
        self.timingHint = timingHint
        self.estimatedResetAt = estimatedResetAt
        self.summary = summary
        self.provider = provider
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, sourceURL, publishedAt, timingHint, estimatedResetAt, summary, provider, source
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(String.self, forKey: .id),
            kind: try values.decode(ResetSignalKind.self, forKey: .kind),
            sourceURL: try values.decode(URL.self, forKey: .sourceURL),
            publishedAt: try values.decodeIfPresent(Date.self, forKey: .publishedAt),
            timingHint: try values.decodeIfPresent(String.self, forKey: .timingHint),
            estimatedResetAt: try values.decodeIfPresent(Date.self, forKey: .estimatedResetAt),
            summary: try values.decodeIfPresent(String.self, forKey: .summary),
            provider: try values.decodeIfPresent(ProviderKind.self, forKey: .provider) ?? .codex,
            source: try values.decodeIfPresent(ResetSignalSource.self, forKey: .source) ?? .tibo
        )
    }
}

struct ResetSignalMonitorStatus: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case idle
        case disabled
        case checked
        case signal
        case unavailable
    }

    let state: State
    let checkedAt: Date?
    let latestSignal: ResetSignal?
    let recentSignals: [ResetSignal]
    let message: String?

    static let idle = ResetSignalMonitorStatus(state: .idle, checkedAt: nil, latestSignal: nil, recentSignals: [], message: nil)
}

struct ResetSignalMonitorUpdate: Sendable {
    let status: ResetSignalMonitorStatus
    let signalToNotify: ResetSignal?
}

func resetSignalSummary(_ signal: ResetSignal, language: AppLanguage) -> String {
    guard signal.provider == .codex else {
        switch signal.kind {
        case .usageReset:
            return tr(language, "Официальный статус Claude сообщает о сбросе или изменении лимита Claude.", "Claude's official status reports a quota reset or change.")
        case .quotaExpansion:
            return tr(language, "Официальный статус Claude сообщает о временном расширении или дополнительном объёме лимита.", "Claude's official status reports a temporary quota expansion or additional allowance.")
        case .bankedReset:
            return tr(language, "Официальный статус Claude сообщает о доступном сохранённом сбросе.", "Claude's official status reports an available banked reset.")
        }
    }
    let original = signal.summary?.lowercased() ?? ""
    let audience: String
    if original.contains("plus") && original.contains("pro") && original.contains("business") {
        audience = tr(language, "для пользователей Plus, Pro и Business", "for Plus, Pro, and Business users")
    } else if original.contains("plus") && original.contains("pro") {
        audience = tr(language, "для пользователей Plus и Pro", "for Plus and Pro users")
    } else if original.contains("all codex users") || original.contains("everyone") || original.contains("for all") {
        audience = tr(language, "для всех пользователей Codex", "for all Codex users")
    } else {
        audience = tr(language, "для подходящих аккаунтов", "for eligible accounts")
    }
    switch signal.kind {
    case .usageReset:
        return tr(language, "Tibo сообщает: лимиты Codex планируют сбросить \(audience).", "Tibo says Codex limits are planned to reset \(audience).")
    case .bankedReset:
        return tr(language, "Tibo сообщает: \(audience) планируют выдать сохранённый сброс лимита (banked reset), который можно применить позже вручную.", "Tibo says \(audience) are planned to receive a banked reset that can be used manually later.")
    case .quotaExpansion:
        return tr(language, "Tibo сообщает о временном расширении лимита \(audience).", "Tibo says there is a temporary quota expansion \(audience).")
    }
}

@MainActor
final class ResetSignalMonitor {
    static let defaultEndpoint = URL(string: "https://api.dayclaw.com/api/source/public/x/thsottiaux/items")!
    static let pollInterval: TimeInterval = 30 * 60

    private let defaults: UserDefaults
    private let endpoint: URL
    private let stateKey = "resetSignals.monitorState.v1"

    init(defaults: UserDefaults = .standard, endpoint: URL = ResetSignalMonitor.defaultEndpoint) {
        self.defaults = defaults
        self.endpoint = endpoint
    }

    func poll() async -> ResetSignalMonitorUpdate {
        do {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 6
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return ingest(try Self.decodeSignals(from: data), checkedAt: .now)
        } catch {
            let stored = loadState()
            return ResetSignalMonitorUpdate(
                status: ResetSignalMonitorStatus(
                    state: .unavailable,
                    checkedAt: .now,
                    latestSignal: stored.latestSignal,
                    recentSignals: stored.recentSignals,
                    message: "Reset signal source is unavailable"
                ),
                signalToNotify: nil
            )
        }
    }

    func ingest(_ signals: [ResetSignal], checkedAt: Date) -> ResetSignalMonitorUpdate {
        var stored = loadState()
        let recentSignals = newestFirst(in: signals).prefix(3)
        let latest = recentSignals.first ?? stored.latestSignal

        guard stored.hasBaseline else {
            stored.hasBaseline = true
            stored.seenIDs = boundedIDs(from: signals.map(\.id))
            stored.latestSignal = latest
            stored.recentSignals = Array(recentSignals)
            stored.lastCheckedAt = checkedAt
            saveState(stored)
            return ResetSignalMonitorUpdate(
                status: ResetSignalMonitorStatus(state: .checked, checkedAt: checkedAt, latestSignal: latest, recentSignals: Array(recentSignals), message: nil),
                signalToNotify: nil
            )
        }

        let seen = Set(stored.seenIDs)
        let newSignals = signals.filter { !seen.contains($0.id) }
        stored.seenIDs = boundedIDs(from: signals.map(\.id) + stored.seenIDs)
        stored.latestSignal = latest
        if !recentSignals.isEmpty {
            stored.recentSignals = Array(recentSignals)
        }
        stored.lastCheckedAt = checkedAt
        saveState(stored)

        let signalToNotify = newest(in: newSignals)
        return ResetSignalMonitorUpdate(
            status: ResetSignalMonitorStatus(
                state: signalToNotify == nil ? .checked : .signal,
                checkedAt: checkedAt,
                latestSignal: latest,
                recentSignals: stored.recentSignals,
                message: nil
            ),
            signalToNotify: signalToNotify
        )
    }

    static func decodeSignals(from data: Data) throws -> [ResetSignal] {
        let feed = try JSONDecoder().decode(Feed.self, from: data)
        guard feed.source.userName.lowercased() == "thsottiaux" else { return [] }

        return feed.items.compactMap { item in
            guard item.author.lowercased() == "thsottiaux",
                  let kind = classify(item.content),
                  let sourceURL = URL(string: item.url)
            else { return nil }
            let publishedAt = parseDate(item.publishedAt)
            let timing = timing(in: item.content, publishedAt: publishedAt)
            return ResetSignal(
                id: item.externalID ?? item.id,
                kind: kind,
                sourceURL: sourceURL,
                publishedAt: publishedAt,
                timingHint: timing.hint,
                estimatedResetAt: timing.estimatedAt,
                summary: summary(from: item.content)
            )
        }
    }

    private static func classify(_ text: String) -> ResetSignalKind? {
        let value = text.lowercased()
        if value.range(of: #"\bbanked\s+reset\b"#, options: .regularExpression) != nil {
            return .bankedReset
        }

        let mentionsReset = value.range(of: #"\b(?:reset|resets|resetting|reseted|restored|restoring)\b"#, options: .regularExpression) != nil
        let mentionsQuota = value.range(of: #"\b(?:codex|usage|rate|quota|limit|limits)\b"#, options: .regularExpression) != nil
        return mentionsReset && mentionsQuota ? .usageReset : nil
    }

    private static func timing(in text: String, publishedAt: Date?) -> (hint: String?, estimatedAt: Date?) {
        let value = text.lowercased()
        if value.contains("end of day") { return ("end of day", nil) }
        if value.range(of: #"\b(?:in|within|~)\s+(?:the\s+)?next\s+hour\b"#, options: .regularExpression) != nil {
            return ("next hour", publishedAt.map { $0.addingTimeInterval(60 * 60) })
        }
        if let match = value.range(of: #"(?:in|within|~)\s+(\d+(?:\.\d+)?)\s*(minutes?|mins?|hours?|hrs?)\b"#, options: .regularExpression) {
            let phrase = String(value[match])
            let number = value[match].split(whereSeparator: { !$0.isNumber && $0 != "." }).first.flatMap { Double($0) }
            let seconds = phrase.contains("min") ? (number ?? 0) * 60 : (number ?? 0) * 60 * 60
            return (phrase, publishedAt.map { $0.addingTimeInterval(seconds) })
        }
        if let explicit = explicitClockTime(in: value, publishedAt: publishedAt) {
            return (explicit.hint, explicit.date)
        }
        if value.contains("today") { return ("today", nil) }
        return (nil, nil)
    }

    private static func explicitClockTime(in value: String, publishedAt: Date?) -> (hint: String, date: Date)? {
        guard let publishedAt,
              let expression = try? NSRegularExpression(
                pattern: #"\b(?:at|around|by|landing(?:\s+at)?|lands?\s+at)\s*(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?\s*(et|est|edt|eastern\s+time|pt|pst|pdt|pacific\s+time|utc|gmt)\b"#,
                options: []
              )
        else { return nil }
        let range = NSRange(value.startIndex..., in: value)
        guard let match = expression.firstMatch(in: value, options: [], range: range),
              let hour = integerCapture(match, group: 1, in: value),
              let zoneText = stringCapture(match, group: 4, in: value),
              let timeZone = sourceTimeZone(for: zoneText)
        else { return nil }
        let minute = integerCapture(match, group: 2, in: value) ?? 0
        guard minute < 60 else { return nil }

        let meridiem = stringCapture(match, group: 3, in: value)?.replacingOccurrences(of: ".", with: "")
        let normalizedHour: Int
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            normalizedHour = meridiem == "pm" && hour != 12 ? hour + 12 : (meridiem == "am" && hour == 12 ? 0 : hour)
        } else {
            guard (0...23).contains(hour) else { return nil }
            normalizedHour = hour
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var day = calendar.dateComponents([.year, .month, .day], from: publishedAt)
        if value.contains("tomorrow") {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: publishedAt) else { return nil }
            day = calendar.dateComponents([.year, .month, .day], from: nextDay)
        }
        day.hour = normalizedHour
        day.minute = minute
        day.second = 0
        guard let candidate = calendar.date(from: day), candidate > publishedAt else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: candidate)
        guard resolved.year == day.year,
              resolved.month == day.month,
              resolved.day == day.day,
              resolved.hour == day.hour,
              resolved.minute == day.minute
        else { return nil }
        return (String(value[Range(match.range, in: value)!]), candidate)
    }

    private static func integerCapture(_ match: NSTextCheckingResult, group: Int, in value: String) -> Int? {
        stringCapture(match, group: group, in: value).flatMap(Int.init)
    }

    private static func stringCapture(_ match: NSTextCheckingResult, group: Int, in value: String) -> String? {
        let range = match.range(at: group)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: value) else { return nil }
        return String(value[swiftRange])
    }

    private static func sourceTimeZone(for raw: String) -> TimeZone? {
        switch raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) {
        case "et", "est", "edt", "eastern time": TimeZone(identifier: "America/New_York")
        case "pt", "pst", "pdt", "pacific time": TimeZone(identifier: "America/Los_Angeles")
        case "utc", "gmt": TimeZone(secondsFromGMT: 0)
        default: nil
        }
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: raw)
    }

    private static func summary(from text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(normalized.prefix(280))
    }

    private func newest(in signals: [ResetSignal]) -> ResetSignal? {
        signals.max { ($0.publishedAt ?? .distantPast) < ($1.publishedAt ?? .distantPast) }
    }

    private func newestFirst(in signals: [ResetSignal]) -> [ResetSignal] {
        signals.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }

    private func loadState() -> StoredState {
        guard let data = defaults.data(forKey: stateKey),
              let value = try? JSONDecoder().decode(StoredState.self, from: data)
        else { return StoredState() }
        return value
    }

    private func saveState(_ state: StoredState) {
        defaults.set(try? JSONEncoder().encode(state), forKey: stateKey)
    }

    private func boundedIDs(from values: [String]) -> [String] {
        Array(NSOrderedSet(array: values).array.compactMap { $0 as? String }.prefix(250))
    }
}

private extension ResetSignalMonitor {
    struct Feed: Decodable {
        let source: Source
        let items: [Item]
    }

    struct Source: Decodable {
        let userName: String

        enum CodingKeys: String, CodingKey {
            case userName = "user_name"
        }
    }

    struct Item: Decodable {
        let id: String
        let externalID: String?
        let content: String
        let url: String
        let author: String
        let publishedAt: String?

        enum CodingKeys: String, CodingKey {
            case id, content, url, author
            case externalID = "external_id"
            case publishedAt = "published_at"
        }
    }

    struct StoredState: Codable {
        var hasBaseline = false
        var seenIDs: [String] = []
        var latestSignal: ResetSignal?
        var recentSignals: [ResetSignal] = []
        var lastCheckedAt: Date?
    }
}
