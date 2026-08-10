import Foundation

struct CodexBarBridgeProvider: Sendable {
    let provider: ProviderKind

    func fetch() async -> ProviderSnapshot {
        guard let executable = ExecutableLocator.locate("codexbar") else {
            return .unavailable(provider, message: "Compatible local provider bridge is not installed")
        }

        let source = provider == .codex ? "oauth" : "auto"
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

    private func chooseWindow(_ usage: [String: Any]) -> QuotaWindow? {
        let candidates = ["primary", "secondary", "tertiary"].compactMap { key -> QuotaWindow? in
            guard let raw = usage[key] as? [String: Any],
                  let used = number(raw["usedPercent"])
            else { return nil }
            let minutes = number(raw["windowMinutes"]).map(Int.init)
            let reset: Date?
            if let string = raw["resetsAt"] as? String {
                reset = ISO8601DateFormatter().date(from: string)
            } else {
                reset = nil
            }
            return QuotaWindow(usedPercent: used, resetsAt: reset, windowMinutes: minutes)
        }
        return candidates.max(by: { ($0.windowMinutes ?? 0) < ($1.windowMinutes ?? 0) })
    }

    private func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, with: "account", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(220)
            .description
    }
}
