import Foundation

/// Watches Claude's public Statuspage for explicit quota/reset announcements.
/// Normal model and service incidents are intentionally ignored: they are not
/// evidence that a user's subscription quota was reset.
@MainActor
final class ClaudeResetSignalMonitor {
    static let defaultEndpoint = URL(string: "https://status.claude.com/api/v2/incidents.json")!

    private let defaults: UserDefaults
    private let endpoint: URL
    private let stateKey = "resetSignals.claudeMonitorState.v1"

    init(defaults: UserDefaults = .standard, endpoint: URL = ClaudeResetSignalMonitor.defaultEndpoint) {
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
                    message: "Claude status source is unavailable"
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
        if !recentSignals.isEmpty { stored.recentSignals = Array(recentSignals) }
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
        let feed = try JSONDecoder().decode(StatusFeed.self, from: data)
        return feed.incidents.flatMap { incident in
            let sourceURL = URL(string: incident.shortlink) ?? URL(string: "https://status.claude.com")!
            let updates: [StatusUpdate] = incident.updates.isEmpty
                ? [StatusUpdate(id: incident.id, body: incident.name, createdAt: incident.updatedAt ?? incident.createdAt)]
                : incident.updates
            return updates.compactMap { update -> ResetSignal? in
                guard let kind = classify(incident.name + " " + update.body) else { return nil }
                return ResetSignal(
                    id: "claude-status-\(incident.id)-\(update.id)",
                    kind: kind,
                    sourceURL: sourceURL,
                    publishedAt: parseDate(update.createdAt) ?? parseDate(incident.updatedAt) ?? parseDate(incident.createdAt),
                    timingHint: nil,
                    estimatedResetAt: nil,
                    summary: summary(from: update.body.isEmpty ? incident.name : update.body),
                    provider: .claude,
                    source: .claudeStatus
                )
            }
        }
    }

    private static func classify(_ text: String) -> ResetSignalKind? {
        let value = text.lowercased()
        let refersToQuota = value.range(of: #"\b(?:usage|quota|limit|limits|allowance|credits?)\b"#, options: .regularExpression) != nil
        guard refersToQuota else { return nil }
        if value.range(of: #"\b(?:reset|resetting|restored|restore)\b"#, options: .regularExpression) != nil {
            return .usageReset
        }
        let refersToExpansion = value.range(of: #"\b(?:temporary|temporarily|increase[ds]?|increased|additional|extra)\b"#, options: .regularExpression) != nil
        return refersToExpansion ? .quotaExpansion : nil
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
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
              let state = try? JSONDecoder().decode(StoredState.self, from: data)
        else { return StoredState() }
        return state
    }

    private func saveState(_ state: StoredState) {
        defaults.set(try? JSONEncoder().encode(state), forKey: stateKey)
    }

    private func boundedIDs(from values: [String]) -> [String] {
        Array(NSOrderedSet(array: values).array.compactMap { $0 as? String }.prefix(250))
    }
}

private extension ClaudeResetSignalMonitor {
    struct StatusFeed: Decodable {
        let incidents: [StatusIncident]
    }

    struct StatusIncident: Decodable {
        let id: String
        let name: String
        let shortlink: String
        let createdAt: String?
        let updatedAt: String?
        let updates: [StatusUpdate]

        enum CodingKeys: String, CodingKey {
            case id, name, shortlink
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case updates = "incident_updates"
        }
    }

    struct StatusUpdate: Decodable {
        let id: String
        let body: String
        let createdAt: String?

        enum CodingKeys: String, CodingKey {
            case id, body
            case createdAt = "created_at"
        }
    }

    struct StoredState: Codable {
        var hasBaseline = false
        var seenIDs: [String] = []
        var latestSignal: ResetSignal?
        var recentSignals: [ResetSignal] = []
    }
}
