import Foundation

struct ClaudeAccessCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let token: String
    let expiresAt: Date
    let subscriptionType: String?

    var description: String { "ClaudeAccessCredential(redacted)" }
    var debugDescription: String { description }
}

enum ClaudeOAuthParser {
    static func credential(_ data: Data) -> ClaudeAccessCredential? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty,
              let milliseconds = number(oauth["expiresAt"]), milliseconds.isFinite
        else { return nil }
        return ClaudeAccessCredential(token: token, expiresAt: Date(timeIntervalSince1970: milliseconds / 1_000),
            subscriptionType: oauth["subscriptionType"] as? String)
    }

    static func usage(_ data: Data, capturedAt: Date = .now, plan: String? = nil) -> ClaudeProviderData? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let standardValues = ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet", "seven_day_fable"]
            .compactMap { (root[$0] as? [String: Any]).flatMap { number($0["utilization"]) } }
        let scopedValues = (root["limits"] as? [[String: Any]] ?? []).compactMap { number($0["percent"]) }
        let standardFractional = !standardValues.contains(where: { $0 > 1 })
        let scopedFractional = !scopedValues.contains(where: { $0 > 1 })
        var meters: [ClaudeQuotaMeter] = []
        var titles = Set<String>()
        func add(id: String, scope: ClaudeQuotaScope, title: String?, value: Any?, reset: Any?, minutes: Int,
                 fractional: Bool) {
            guard let raw = number(value), raw.isFinite else { return }
            let used = min(100, max(0, fractional ? raw * 100 : raw))
            let normalizedTitle = title?.lowercased()
            if let normalizedTitle, titles.contains(normalizedTitle) { return }
            if let normalizedTitle { titles.insert(normalizedTitle) }
            meters.append(ClaudeQuotaMeter(id: id, scope: scope, providerTitle: title,
                window: QuotaWindow(usedPercent: used, resetsAt: date(reset as? String), windowMinutes: minutes), usageKnown: true))
        }
        if let five = root["five_hour"] as? [String: Any] {
            add(id: "claude-session", scope: .session, title: nil, value: five["utilization"], reset: five["resets_at"], minutes: 300,
                fractional: standardFractional)
        }
        if let week = root["seven_day"] as? [String: Any] {
            add(id: "claude-weekly", scope: .weekly, title: nil, value: week["utilization"], reset: week["resets_at"], minutes: 10_080,
                fractional: standardFractional)
        }
        for limit in root["limits"] as? [[String: Any]] ?? [] {
            guard limit["kind"] as? String == "weekly_scoped", limit["group"] as? String == "weekly",
                  let scope = limit["scope"] as? [String: Any], let model = scope["model"] as? [String: Any],
                  let title = model["display_name"] as? String, !title.isEmpty else { continue }
            let modelID = model["id"] as? String ?? title
            let modelSlug = slug(modelID)
            guard !modelSlug.isEmpty, !modelSlug.hasSuffix("all-models"), slug(title) != "all-models" else { continue }
            add(id: "claude-weekly-scoped-\(modelSlug)", scope: .modelWeekly, title: title,
                value: limit["percent"], reset: limit["resets_at"], minutes: 10_080, fractional: scopedFractional)
        }
        for (key, value) in root where key.hasPrefix("seven_day_") {
            guard let window = value as? [String: Any] else { continue }
            let title = key.dropFirst("seven_day_".count).split(separator: "_").map { $0.capitalized }.joined(separator: " ")
            add(id: "claude-\(key.replacingOccurrences(of: "_", with: "-"))", scope: .modelWeekly,
                title: title, value: window["utilization"], reset: window["resets_at"], minutes: 10_080,
                fractional: standardFractional)
        }
        guard let limiting = meters.min(by: { $0.window.remainingPercent < $1.window.remainingPercent }) else { return nil }
        return ClaudeProviderData(snapshot: ProviderSnapshot(provider: .claude, state: .connected,
            quota: limiting.window, source: "Claude Code · OAuth", message: nil,
            updatedAt: capturedAt, history: []),
            accountDetails: ClaudeAccountDetails(quotaMeters: meters, planName: plan, creditBalance: nil))
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        if let parsed = formatter.date(from: value) { return parsed }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private static func slug(_ value: String) -> String {
        value.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
    }
}

actor ClaudeOAuthUsageProvider {
    static let shared = ClaudeOAuthUsageProvider()

    typealias Reader = @Sendable () async -> Data?
    typealias Transport = @Sendable (URLRequest) async -> (Int, Data, String?)
    private let reader: Reader
    private let transport: Transport

    init(reader: @escaping Reader = ClaudeOAuthUsageProvider.systemKeychainRead,
         transport: @escaping Transport = ClaudeOAuthUsageProvider.liveTransport) {
        self.reader = reader
        self.transport = transport
    }

    private var credential: ClaudeAccessCredential?
    private var pausedForUnchangedToken = false
    private var pausedForPermission = false
    private var retryAt: Date?
    private var lastError: String?
    private var lastSuccess: Date?
    private var pending: Task<ClaudeProviderData, Never>?

    var status: (lastSuccess: Date?, lastError: String?, permissionDenied: Bool) {
        (lastSuccess, lastError, pausedForPermission)
    }

    func resumeAfterUserAction() {
        pausedForUnchangedToken = false
        pausedForPermission = false
    }

    func resumeAfterManualRefresh() { pausedForUnchangedToken = false }

    func fetch(authorized: Bool) async -> ClaudeProviderData {
        guard authorized else { return .unavailable(message: "Connect Claude Code in Settings to allow Keychain access") }
        if let pending { return await pending.value }
        let task = Task { await self.performFetch() }
        pending = task
        let result = await task.value
        pending = nil
        return result
    }

    private func performFetch() async -> ClaudeProviderData {
        if pausedForPermission { return .unavailable(message: "Keychain access was denied. Press Connect Claude Code to try again") }
        if pausedForUnchangedToken { return .unavailable(message: "Claude Code has not renewed its login. Open Claude Code, then refresh") }
        if let retryAt, retryAt > .now {
            return .unavailable(message: "Anthropic rate limit. Try again after \(retryAt.formatted(date: .omitted, time: .shortened))")
        }
        if credential == nil || credential!.expiresAt <= .now {
            guard await readCredential() else { return .unavailable(message: lastError ?? "Claude Code login is unavailable") }
        }
        guard let current = credential else { return .unavailable(message: "Claude Code login is unavailable") }
        let response = await request(token: current.token)
        if response.status == 401 {
            credential = nil
            guard await readCredential() else { return .unavailable(message: lastError ?? "Claude Code login is unavailable") }
            guard let renewed = credential, renewed.token != current.token else {
                pausedForUnchangedToken = true
                lastError = "Claude Code has not renewed its login. Open Claude Code, then refresh"
                return .unavailable(message: lastError!)
            }
            let second = await request(token: renewed.token)
            return result(second, plan: renewed.subscriptionType)
        }
        return result(response, plan: current.subscriptionType)
    }

    private func result(_ response: (status: Int, data: Data, retryAfter: String?), plan: String?) -> ClaudeProviderData {
        switch response.status {
        case 200:
            guard let parsed = ClaudeOAuthParser.usage(response.data, plan: plan) else {
                lastError = "Claude Code returned unreadable quota data"
                return .unavailable(message: lastError!)
            }
            lastSuccess = parsed.snapshot.updatedAt
            lastError = nil
            return parsed
        case 401:
            credential = nil
            pausedForUnchangedToken = true
            lastError = "Claude Code has not renewed its login. Open Claude Code, then refresh"
        case 429:
            retryAt = Self.retryDate(response.retryAfter)
            lastError = "Anthropic rate limit"
        default:
            lastError = response.status == 0 ? "Claude Code quota request failed" : "Claude Code quota request failed (HTTP \(response.status))"
        }
        return .unavailable(message: lastError!)
    }

    static func retryDate(_ value: String?, now: Date = .now) -> Date {
        let minimum = now.addingTimeInterval(60)
        guard let value else { return minimum }
        if let seconds = TimeInterval(value) { return max(minimum, now.addingTimeInterval(seconds)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        return max(minimum, formatter.date(from: value) ?? minimum)
    }

    private func readCredential() async -> Bool {
        guard let data = await reader(), let parsed = ClaudeOAuthParser.credential(data) else {
            pausedForPermission = true
            lastError = "Claude Code Keychain access was denied or its login is unavailable. Press Connect Claude Code to try again"
            return false
        }
        credential = parsed
        lastError = nil
        return true
    }

    private static func systemKeychainRead() async -> Data? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-a", NSUserName(), "-w"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return task.terminationStatus == 0 ? data : nil
        } catch {
            return nil
        }
    }

    private func request(token: String) async -> (status: Int, data: Data, retryAfter: String?) {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-code/\(Self.userAgentVersion)", forHTTPHeaderField: "User-Agent")
        return await transport(request)
    }

    private static func claudeVersion() -> String {
        guard let path = ExecutableLocator.locate("claude") else { return "2.1.0" }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["--version"]
        task.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            task.waitUntilExit()
            if let range = output.range(of: #"[0-9]+\.[0-9]+\.[0-9]+"#, options: .regularExpression) {
                return String(output[range])
            }
        } catch {}
        return "2.1.0"
    }

    private static let userAgentVersion = claudeVersion()

    private static func liveTransport(_ request: URLRequest) async -> (Int, Data, String?) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else { return (0, Data(), nil) }
            return (response.statusCode, data, response.value(forHTTPHeaderField: "Retry-After"))
        } catch { return (0, Data(), nil) }
    }
}
