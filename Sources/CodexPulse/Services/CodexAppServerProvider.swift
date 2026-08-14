import Foundation

struct CodexProviderData: Sendable {
    let snapshot: ProviderSnapshot
    let accountSummary: AccountUsageSummary?
    let accountDaily: [AccountDailyUsage]
    let accountDetails: CodexAccountDetails
}

struct CodexAppServerProvider: Sendable {
    func fetch() async -> ProviderSnapshot {
        await fetchData().snapshot
    }

    func fetchData() async -> CodexProviderData {
        guard let executable = ExecutableLocator.locate("codex") else {
            return CodexProviderData(
                snapshot: .unavailable(.codex, message: "Codex CLI is not installed"),
                accountSummary: nil,
                accountDaily: [],
                accountDetails: .empty
            )
        }

        do {
            let data = try await CodexAppServerClient(executable: executable).readAccountData()

            return CodexProviderData(
                snapshot: ProviderSnapshot(
                    provider: .codex,
                    state: .connected,
                    quota: data.window,
                    source: "Codex App Server",
                    message: nil,
                    updatedAt: .now,
                    history: []
                ),
                accountSummary: data.summary,
                accountDaily: data.daily,
                accountDetails: data.details
            )
        } catch {
            return CodexProviderData(
                snapshot: .unavailable(.codex, message: sanitizedError(error.localizedDescription)),
                accountSummary: nil,
                accountDaily: [],
                accountDetails: .empty
            )
        }
    }

    private func sanitizedError(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, with: "account", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(220)
            .description
    }
}

private enum CodexAppServerClientError: LocalizedError {
    case launch(String)
    case protocolFailure(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case let .launch(message): message
        case let .protocolFailure(message): message
        case .timeout: "Codex App Server timed out"
        }
    }
}

private final class CodexAppServerClient: @unchecked Sendable {
    private let executable: String
    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()
    private let lock = NSLock()

    private var outputBuffer = ""
    private var errorBuffer = ""
    private var sentRequests = false
    private var completed = false
    private var continuation: CheckedContinuation<CodexServerData, Error>?
    private var quotaWindow: QuotaWindow?
    private var accountSummary: AccountUsageSummary?
    private var accountDaily: [AccountDailyUsage] = []
    private var accountDetails = CodexAccountDetails.empty
    private var receivedUsage = false

    init(executable: String) {
        self.executable = executable
    }

    func readAccountData(timeout: TimeInterval = 18) async throws -> CodexServerData {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            configureProcess()

            do {
                try process.run()
                try send([
                    "method": "initialize",
                    "id": 0,
                    "params": [
                        "clientInfo": [
                            "name": "codex_pulse",
                            "title": "Codex Pulse",
                            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.5.0",
                        ],
                    ],
                ])
            } catch {
                finish(.failure(CodexAppServerClientError.launch(error.localizedDescription)))
                return
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self else { return }
                if let window = self.currentQuotaWindow() {
                    self.finish(.success(CodexServerData(window: window, summary: self.accountSummary, daily: self.accountDaily, details: self.accountDetails)))
                } else {
                    self.finish(.failure(CodexAppServerClientError.timeout))
                }
            }
        }
    }

    private func configureProcess() {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", environment["PATH"] ?? ""]
            .joined(separator: ":")
        process.environment = environment

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consumeOutput(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consumeError(handle.availableData)
        }
        process.terminationHandler = { [weak self] finished in
            guard let self else { return }
            let message = currentError().isEmpty
                ? "Codex App Server ended before returning quota data (status \(finished.terminationStatus))"
                : currentError()
            finish(.failure(CodexAppServerClientError.protocolFailure(message)))
        }
    }

    private func consumeOutput(_ data: Data) {
        guard !data.isEmpty else { return }
        let chunk = String(decoding: data, as: UTF8.self)
        var lines: [String] = []

        lock.lock()
        outputBuffer += chunk
        while let newline = outputBuffer.firstIndex(of: "\n") {
            lines.append(String(outputBuffer[..<newline]))
            outputBuffer.removeSubrange(...newline)
        }
        lock.unlock()

        lines.forEach(handleLine)
    }

    private func consumeError(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        errorBuffer += String(decoding: data, as: UTF8.self)
        lock.unlock()
    }

    private func handleLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = number(object["id"]).map(Int.init)
        else { return }

        if id == 0 {
            lock.lock()
            let shouldSend = !sentRequests && !completed
            sentRequests = true
            lock.unlock()
            guard shouldSend else { return }

            do {
                try send(["method": "initialized", "params": [:]])
                try send(["method": "account/rateLimits/read", "id": 6])
                try send(["method": "account/usage/read", "id": 7])
            } catch {
                finish(.failure(CodexAppServerClientError.protocolFailure(error.localizedDescription)))
            }
            return
        }

        if id == 6,
           let result = object["result"] as? [String: Any] {
            let details = parseAccountDetails(result)
            guard let window = chooseQuotaWindow(from: details) else { return }
            lock.lock()
            quotaWindow = window
            accountDetails = details
            let usageReady = receivedUsage
            let summary = accountSummary
            let daily = accountDaily
            lock.unlock()
            if usageReady { finish(.success(CodexServerData(window: window, summary: summary, daily: daily, details: details))) }
            return
        }

        if id == 7 {
            let usage = parseAccountUsage(object["result"] as? [String: Any])
            lock.lock()
            accountSummary = usage.summary
            accountDaily = usage.daily
            receivedUsage = true
            let window = quotaWindow
            let details = accountDetails
            lock.unlock()
            if let window { finish(.success(CodexServerData(window: window, summary: usage.summary, daily: usage.daily, details: details))) }
        }
    }

    private func send(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        var payload = data
        payload.append(0x0A)
        try inputPipe.fileHandleForWriting.write(contentsOf: payload)
    }

    private func parseAccountDetails(_ result: [String: Any]) -> CodexAccountDetails {
        var buckets: [CodexQuotaBucket] = []
        if let byID = result["rateLimitsByLimitId"] as? [String: Any] {
            for id in byID.keys.sorted() {
                guard let raw = byID[id] as? [String: Any] else { continue }
                buckets.append(parseBucket(raw, fallbackID: id))
            }
        }
        if buckets.isEmpty, let raw = result["rateLimits"] as? [String: Any] {
            let fallbackID = raw["limitId"] as? String ?? "codex"
            buckets = [parseBucket(raw, fallbackID: fallbackID)]
        }

        let preferred = buckets.first(where: { $0.id.lowercased() == "codex" }) ?? buckets.first
        let resetCredits = (result["rateLimitResetCredits"] as? [String: Any])
            .flatMap { int64($0["availableCount"]) }
            .map(Int.init) ?? 0
        return CodexAccountDetails(
            quotaBuckets: buckets,
            planType: preferred?.planType ?? buckets.compactMap(\.planType).first,
            creditBalance: preferred?.creditBalance ?? buckets.compactMap(\.creditBalance).first,
            resetCreditsAvailable: resetCredits
        )
    }

    private func parseBucket(_ raw: [String: Any], fallbackID: String) -> CodexQuotaBucket {
        let credits = raw["credits"] as? [String: Any]
        return CodexQuotaBucket(
            id: raw["limitId"] as? String ?? fallbackID,
            name: raw["limitName"] as? String,
            planType: raw["planType"] as? String,
            primary: parseWindow(raw["primary"]),
            secondary: parseWindow(raw["secondary"]),
            creditBalance: credits?["balance"] as? String,
            hasCredits: credits?["hasCredits"] as? Bool,
            unlimitedCredits: credits?["unlimited"] as? Bool ?? false
        )
    }

    private func parseWindow(_ value: Any?) -> QuotaWindow? {
        guard let raw = value as? [String: Any], let used = number(raw["usedPercent"]) else { return nil }
        return QuotaWindow(
            usedPercent: used,
            resetsAt: number(raw["resetsAt"]).map { Date(timeIntervalSince1970: $0) },
            windowMinutes: number(raw["windowDurationMins"]).map(Int.init)
        )
    }

    private func chooseQuotaWindow(from details: CodexAccountDetails) -> QuotaWindow? {
        let preferred = details.quotaBuckets.first(where: { $0.id.lowercased() == "codex" })
        let preferredWindows = preferred.map { [$0.primary, $0.secondary].compactMap { $0 } } ?? []
        let allWindows = details.quotaBuckets.flatMap { [$0.primary, $0.secondary].compactMap { $0 } }
        return (preferredWindows.isEmpty ? allWindows : preferredWindows)
            .max(by: { ($0.windowMinutes ?? 0) < ($1.windowMinutes ?? 0) })
    }

    private func parseAccountUsage(_ result: [String: Any]?) -> (summary: AccountUsageSummary?, daily: [AccountDailyUsage]) {
        guard let result else { return (nil, []) }
        let summaryRaw = result["summary"] as? [String: Any]
        let summary = summaryRaw.map {
            AccountUsageSummary(
                lifetimeTokens: int64($0["lifetimeTokens"]),
                peakDailyTokens: int64($0["peakDailyTokens"]),
                longestRunningTurnSec: int64($0["longestRunningTurnSec"]),
                currentStreakDays: int64($0["currentStreakDays"]),
                longestStreakDays: int64($0["longestStreakDays"])
            )
        }
        let daily = (result["dailyUsageBuckets"] as? [[String: Any]] ?? []).compactMap { item -> AccountDailyUsage? in
            guard let date = item["startDate"] as? String, let tokens = int64(item["tokens"]) else { return nil }
            return AccountDailyUsage(startDate: date, tokens: tokens)
        }
        return (summary, daily)
    }

    private func int64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        return nil
    }

    private func currentQuotaWindow() -> QuotaWindow? {
        lock.lock()
        defer { lock.unlock() }
        return quotaWindow
    }

    private func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private func currentError() -> String {
        lock.lock()
        defer { lock.unlock() }
        return errorBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func finish(_ result: Result<CodexServerData, Error>) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        try? inputPipe.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        continuation?.resume(with: result)
    }
}

private struct CodexServerData: Sendable {
    let window: QuotaWindow
    let summary: AccountUsageSummary?
    let daily: [AccountDailyUsage]
    let details: CodexAccountDetails
}
