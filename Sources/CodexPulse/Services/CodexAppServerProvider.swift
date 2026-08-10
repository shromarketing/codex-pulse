import Foundation

struct CodexAppServerProvider: Sendable {
    func fetch() async -> ProviderSnapshot {
        guard let executable = ExecutableLocator.locate("codex") else {
            return .unavailable(.codex, message: "Codex CLI is not installed")
        }

        do {
            let window = try await CodexAppServerClient(executable: executable).readRateLimit()

            return ProviderSnapshot(
                provider: .codex,
                state: .connected,
                quota: window,
                source: "Codex App Server",
                message: nil,
                updatedAt: .now,
                history: []
            )
        } catch {
            return .unavailable(.codex, message: sanitizedError(error.localizedDescription))
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
    private var continuation: CheckedContinuation<QuotaWindow, Error>?

    init(executable: String) {
        self.executable = executable
    }

    func readRateLimit(timeout: TimeInterval = 18) async throws -> QuotaWindow {
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
                            "version": "0.1.0",
                        ],
                    ],
                ])
            } catch {
                finish(.failure(CodexAppServerClientError.launch(error.localizedDescription)))
                return
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(.failure(CodexAppServerClientError.timeout))
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
            } catch {
                finish(.failure(CodexAppServerClientError.protocolFailure(error.localizedDescription)))
            }
            return
        }

        guard id == 6,
              let result = object["result"] as? [String: Any],
              let window = chooseQuotaWindow(from: result)
        else { return }
        finish(.success(window))
    }

    private func send(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        var payload = data
        payload.append(0x0A)
        try inputPipe.fileHandleForWriting.write(contentsOf: payload)
    }

    private func chooseQuotaWindow(from result: [String: Any]) -> QuotaWindow? {
        let rateLimits = (result["rateLimitsByLimitId"] as? [String: Any])?["codex"] as? [String: Any]
            ?? result["rateLimits"] as? [String: Any]
        guard let rateLimits else { return nil }

        let candidates = ["primary", "secondary", "tertiary"].compactMap { key -> QuotaWindow? in
            guard let raw = rateLimits[key] as? [String: Any],
                  let used = number(raw["usedPercent"])
            else { return nil }
            let minutes = number(raw["windowDurationMins"]).map(Int.init)
            let reset = number(raw["resetsAt"]).map { Date(timeIntervalSince1970: $0) }
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

    private func currentError() -> String {
        lock.lock()
        defer { lock.unlock() }
        return errorBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func finish(_ result: Result<QuotaWindow, Error>) {
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
