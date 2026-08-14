import Foundation

struct CodexBarBridgeProvider: Sendable {
    let provider: ProviderKind

    func fetch() async -> ProviderSnapshot {
        if provider == .claude {
            return await fetchClaudeData(source: .automatic).snapshot
        }
        return await fetchSnapshot(source: "oauth")
    }

    func fetchClaudeData(
        source: ClaudeUsageSource,
        allowBrowserCookieImport: Bool = false
    ) async -> ClaudeProviderData {
        guard let sourceValue = source.commandValue else {
            return .unavailable(message: "Claude Web is not connected")
        }
        guard let executable = ExecutableLocator.locate("codexbar") else {
            return .unavailable(message: "Compatible local provider bridge is not installed")
        }
        if source == .web && !allowBrowserCookieImport {
            return .unavailable(message: "Chrome session access needs explicit confirmation")
        }

        do {
            let result = try await CommandRunner.run(
                executable: executable,
                arguments: [
                    "usage",
                    "--provider", ProviderKind.claude.rawValue,
                    "--source", sourceValue,
                    "--json-only",
                ],
                timeout: 25,
                environmentOverrides: allowBrowserCookieImport
                    ? ["CODEXBAR_ALLOW_BROWSER_COOKIE_IMPORT": "1"]
                    : [:]
            )
            guard let data = result.stdout.data(using: .utf8) else {
                return .unavailable(message: "Claude returned an unreadable response")
            }
            return Self.parseClaudePayload(data, requestedSource: source)
        } catch {
            return .unavailable(message: sanitize(error.localizedDescription))
        }
    }

    private func fetchSnapshot(source: String) async -> ProviderSnapshot {
        guard let executable = ExecutableLocator.locate("codexbar") else {
            return .unavailable(provider, message: "Compatible local provider bridge is not installed")
        }

        do {
            let result = try await CommandRunner.run(
                executable: executable,
                arguments: [
                    "usage",
                    "--provider", provider.rawValue,
                    "--source", source,
                    "--json-only",
                ],
                timeout: 25
            )
            guard let data = result.stdout.data(using: .utf8),
                  let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let item = array.first
            else {
                return .unavailable(provider, message: "Provider returned an unreadable response")
            }

            if let error = item["error"] as? [String: Any] {
                return .unavailable(provider, message: sanitize(error["message"] as? String ?? "Provider is not connected"))
            }

            guard let usage = item["usage"] as? [String: Any],
                  let quota = chooseWindow(usage)
            else {
                return .unavailable(provider, message: "Connect \(provider.displayName) to read quota data")
            }

            return ProviderSnapshot(
                provider: provider,
                state: .connected,
                quota: quota,
                source: "Local compatibility bridge",
                message: nil,
                updatedAt: .now,
                history: []
            )
        } catch {
            return .unavailable(provider, message: sanitize(error.localizedDescription))
        }
    }

    static func parseClaudePayload(_ data: Data, requestedSource: ClaudeUsageSource) -> ClaudeProviderData {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let item = array.first
        else {
            return .unavailable(message: "Claude returned an unreadable response")
        }

        if let error = item["error"] as? [String: Any] {
            return .unavailable(message: sanitize(error["message"] as? String ?? "Claude Web is not connected"))
        }
        guard let usage = item["usage"] as? [String: Any] else {
            return .unavailable(message: "Claude did not return quota data")
        }

        var meters: [ClaudeQuotaMeter] = []
        if let primary = quotaWindow(usage["primary"]) {
            meters.append(ClaudeQuotaMeter(
                id: "claude-session",
                scope: .session,
                providerTitle: nil,
                window: primary.window,
                usageKnown: primary.usageKnown
            ))
        }
        if let secondary = quotaWindow(usage["secondary"]) {
            meters.append(ClaudeQuotaMeter(
                id: "claude-weekly",
                scope: .weekly,
                providerTitle: nil,
                window: secondary.window,
                usageKnown: secondary.usageKnown
            ))
        }
        if let tertiary = quotaWindow(usage["tertiary"]) {
            meters.append(ClaudeQuotaMeter(
                id: "claude-model-weekly",
                scope: .modelWeekly,
                providerTitle: nil,
                window: tertiary.window,
                usageKnown: tertiary.usageKnown
            ))
        }
        if let extras = usage["extraRateWindows"] as? [[String: Any]] {
            for extra in extras {
                guard let rawWindow = extra["window"], let parsed = quotaWindow(rawWindow) else { continue }
                let id = nonEmptyString(extra["id"]) ?? "claude-model-\(meters.count)"
                let title = nonEmptyString(extra["title"])
                let known = (extra["usageKnown"] as? Bool) ?? parsed.usageKnown
                meters.removeAll { $0.id == id }
                meters.append(ClaudeQuotaMeter(
                    id: id,
                    scope: .modelWeekly,
                    providerTitle: title,
                    window: parsed.window,
                    usageKnown: known
                ))
            }
        }

        let knownWindows = meters.filter(\.usageKnown)
        guard let limiting = knownWindows.min(by: { $0.window.remainingPercent < $1.window.remainingPercent }) else {
            return .unavailable(message: "Claude returned reset details but no readable quota percentages")
        }

        let identity = usage["identity"] as? [String: Any]
        let plan = nonEmptyString(identity?["loginMethod"])
            ?? nonEmptyString(usage["loginMethod"])
        let credits = (item["credits"] as? [String: Any]).flatMap { displayNumber($0["remaining"]) }
        let rawSource = nonEmptyString(item["source"])
        let sourceLabel: String = switch requestedSource {
        case .browserExtension: "Claude Web via Pulse Connector"
        case .web: "Claude Web via local bridge"
        case .oauth: "Claude OAuth via local bridge"
        case .automatic: rawSource.map { "Claude \($0) via local bridge" } ?? "Claude via local bridge"
        case .off: ""
        }

        return ClaudeProviderData(
            snapshot: ProviderSnapshot(
                provider: .claude,
                state: .connected,
                quota: limiting.window,
                source: sourceLabel,
                message: nil,
                updatedAt: parseDate(usage["updatedAt"] as? String) ?? .now,
                history: []
            ),
            accountDetails: ClaudeAccountDetails(
                quotaMeters: meters,
                planName: plan,
                creditBalance: credits
            )
        )
    }

    private func chooseWindow(_ usage: [String: Any]) -> QuotaWindow? {
        let candidates = ["primary", "secondary", "tertiary"].compactMap { key in
            Self.quotaWindow(usage[key])?.window
        }
        return candidates.max(by: { ($0.windowMinutes ?? 0) < ($1.windowMinutes ?? 0) })
    }

    private static func quotaWindow(_ value: Any?) -> (window: QuotaWindow, usageKnown: Bool)? {
        guard let raw = value as? [String: Any],
              let used = number(raw["usedPercent"])
        else { return nil }
        let minutes = number(raw["windowMinutes"]).map(Int.init)
        let reset = parseDate(raw["resetsAt"] as? String)
        let synthetic = (raw["isSyntheticPlaceholder"] as? Bool) ?? false
        return (
            QuotaWindow(usedPercent: used, resetsAt: reset, windowMinutes: minutes),
            !synthetic
        )
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func displayNumber(_ value: Any?) -> String? {
        guard let value = number(value) else { return nil }
        return value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }

    private func sanitize(_ value: String) -> String { Self.sanitize(value) }

    private static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, with: "account", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(220)
            .description
    }
}
