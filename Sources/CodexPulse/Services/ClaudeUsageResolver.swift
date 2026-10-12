import Foundation

enum ClaudeUsageResolver {
    static let staleLabelAfter: TimeInterval = 5 * 60

    static func valid(_ data: ClaudeProviderData?, now: Date = .now) -> ClaudeProviderData? {
        guard let data, data.snapshot.state == .connected,
              data.snapshot.updatedAt <= now.addingTimeInterval(60) else { return nil }
        if data.snapshot.source.contains("local file") && now.timeIntervalSince(data.snapshot.updatedAt) > 30 * 60 {
            return nil
        }
        let meters = data.accountDetails.quotaMeters.filter {
            $0.usageKnown && ($0.window.resetsAt == nil || $0.window.resetsAt! > now)
        }
        guard let limiting = meters.min(by: { $0.window.remainingPercent < $1.window.remainingPercent }) else { return nil }
        return ClaudeProviderData(snapshot: ProviderSnapshot(provider: .claude, state: .connected,
            quota: limiting.window, source: data.snapshot.source, message: nil,
            updatedAt: data.snapshot.updatedAt, history: []),
            accountDetails: ClaudeAccountDetails(quotaMeters: meters,
                planName: data.accountDetails.planName, creditBalance: data.accountDetails.creditBalance))
    }

    static func select(_ candidates: [ClaudeProviderData?], now: Date = .now) -> ClaudeProviderData? {
        let validCandidates = candidates.compactMap { valid($0, now: now) }
        if let fresh = validCandidates.first(where: { now.timeIntervalSince($0.snapshot.updatedAt) <= staleLabelAfter }) {
            return fresh
        }
        return validCandidates.max(by: { $0.snapshot.updatedAt < $1.snapshot.updatedAt })
    }

    static func inheritingResetTimes(_ file: ClaudeProviderData?, from known: [ClaudeProviderData?]) -> ClaudeProviderData? {
        guard let file else { return nil }
        let meters = file.accountDetails.quotaMeters.map { meter in
            guard let previous = known.compactMap({ $0?.accountDetails.quotaMeters.first(where: { $0.id == meter.id }) }).first,
                  let reset = previous.window.resetsAt,
                  let minutes = meter.window.windowMinutes else { return meter }
            var next = reset
            let duration = TimeInterval(minutes * 60)
            while next <= file.snapshot.updatedAt { next.addTimeInterval(duration) }
            return ClaudeQuotaMeter(id: meter.id, scope: meter.scope, providerTitle: meter.providerTitle,
                window: QuotaWindow(usedPercent: meter.window.usedPercent, resetsAt: next,
                    windowMinutes: minutes), usageKnown: true)
        }
        return ClaudeProviderData(snapshot: file.snapshot,
            accountDetails: ClaudeAccountDetails(quotaMeters: meters, planName: file.accountDetails.planName,
                creditBalance: nil))
    }
}

enum ClaudePlanUsageReader {
    static func read(fileURL: URL? = nil) -> ClaudeProviderData? {
        let url = fileURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let samples = root["samples"] as? [[String: Any]],
              let latest = samples.max(by: { timestamp($0) < timestamp($1) }),
              let usage = latest["u"] as? [String: Any],
              timestamp(latest).isFinite, timestamp(latest) > 0
        else { return nil }
        let capturedAt = Date(timeIntervalSince1970: timestamp(latest) / 1_000)
        var meters: [ClaudeQuotaMeter] = []
        for (key, id, scope, minutes) in [
            ("fh", "claude-session", ClaudeQuotaScope.session, 300),
            ("sd", "claude-weekly", ClaudeQuotaScope.weekly, 10_080)
        ] {
            guard let value = (usage[key] as? NSNumber)?.doubleValue, value.isFinite else { continue }
            meters.append(ClaudeQuotaMeter(id: id, scope: scope, providerTitle: nil,
                window: QuotaWindow(usedPercent: min(100, max(0, value)), resetsAt: nil,
                    windowMinutes: minutes), usageKnown: true))
        }
        guard let limiting = meters.min(by: { $0.window.remainingPercent < $1.window.remainingPercent }) else { return nil }
        return ClaudeProviderData(snapshot: ProviderSnapshot(provider: .claude, state: .connected,
            quota: limiting.window, source: "Claude app · local file", message: nil,
            updatedAt: capturedAt, history: []),
            accountDetails: ClaudeAccountDetails(quotaMeters: meters, planName: nil, creditBalance: nil))
    }

    private static func timestamp(_ sample: [String: Any]) -> Double {
        (sample["t"] as? NSNumber)?.doubleValue ?? 0
    }
}
