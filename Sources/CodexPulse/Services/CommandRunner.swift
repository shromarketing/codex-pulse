import Foundation

struct CommandResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum CommandRunnerError: LocalizedError {
    case executableNotFound(String)
    case timedOut(String)
    case failedToLaunch(String)

    var errorDescription: String? {
        switch self {
        case let .executableNotFound(name): "Executable not found: \(name)"
        case let .timedOut(name): "Command timed out: \(name)"
        case let .failedToLaunch(message): message
        }
    }
}

enum ExecutableLocator {
    static func locate(_ name: String) -> String? {
        let candidates: [String]
        switch name {
        case "codex":
            candidates = [
                "/Applications/ChatGPT.app/Contents/Resources/codex",
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex",
                "/usr/bin/codex",
            ]
        case "codexbar":
            candidates = [
                "/opt/homebrew/bin/codexbar",
                "/usr/local/bin/codexbar",
            ]
        case "claude":
            candidates = [
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude",
                NSString(string: "~/.local/bin/claude").expandingTildeInPath,
            ]
        default:
            candidates = ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
        }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }
}

enum CommandRunner {
    static func run(
        executable: String,
        arguments: [String],
        input: String? = nil,
        timeout: TimeInterval = 25
    ) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdinPipe = Pipe()
            let gate = CompletionGate()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            if input != nil { process.standardInput = stdinPipe }

            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = [
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/usr/bin",
                "/bin",
                environment["PATH"] ?? "",
            ].joined(separator: ":")
            process.environment = environment

            let timeoutWork = DispatchWorkItem {
                guard gate.claim() else { return }
                if process.isRunning { process.terminate() }
                continuation.resume(throwing: CommandRunnerError.timedOut(URL(fileURLWithPath: executable).lastPathComponent))
            }

            process.terminationHandler = { finishedProcess in
                guard gate.claim() else { return }
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: CommandResult(
                    stdout: String(decoding: stdoutData, as: UTF8.self),
                    stderr: String(decoding: stderrData, as: UTF8.self),
                    exitCode: finishedProcess.terminationStatus
                ))
            }

            do {
                try process.run()
            } catch {
                if gate.claim() {
                    continuation.resume(throwing: CommandRunnerError.failedToLaunch(error.localizedDescription))
                }
                return
            }

            if let input, let data = input.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
                try? stdinPipe.fileHandleForWriting.close()
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
        }
    }
}

private final class CompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }
}
