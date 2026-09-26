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
    static func locate(
        _ name: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        applicationDirectories: [String]? = nil
    ) -> String? {
        if name == "codex" {
            if let override = environment["CODEX_PULSE_CODEX_PATH"], !override.isEmpty {
                return isExecutable(override) ? override : nil
            }
            let directories = applicationDirectories ?? ["/Applications", "\(homeDirectory)/Applications"]
            return codexCandidates(environment: environment, homeDirectory: homeDirectory, applicationDirectories: directories)
                .first(where: isExecutable)
        }

        let candidates: [String]
        switch name {
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

    static func missingCodexMessage(language: AppLanguage, environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let invalidOverride = environment["CODEX_PULSE_CODEX_PATH"].map { !$0.isEmpty } ?? false
        let prefix = invalidOverride
            ? (language == .russian ? "Путь CODEX_PULSE_CODEX_PATH не ведёт к исполняемому файлу. " : "CODEX_PULSE_CODEX_PATH is not executable. ")
            : (language == .russian ? "Codex CLI не найден. " : "Codex CLI was not found. ")
        let checked = language == .russian
            ? "\(invalidOverride ? "Обычные места поиска" : "Проверены"): /Applications и ~/Applications (ChatGPT.app/codex-cli, старые ChatGPT.app и Codex.app), /opt/homebrew/bin, /usr/local/bin, ~/.local/bin и PATH. Укажите CLI через CODEX_PULSE_CODEX_PATH."
            : "\(invalidOverride ? "Usual search locations" : "Checked"): /Applications and ~/Applications (ChatGPT.app/codex-cli, legacy ChatGPT.app and Codex.app), /opt/homebrew/bin, /usr/local/bin, ~/.local/bin, and PATH. Set CODEX_PULSE_CODEX_PATH to the CLI."
        return prefix + checked
    }

    private static func isExecutable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    private static func codexCandidates(
        environment: [String: String],
        homeDirectory: String,
        applicationDirectories: [String]
    ) -> [String] {
        var paths: [String] = []
        for directory in applicationDirectories {
            let packageDirectory = "\(directory)/ChatGPT.app/Contents/Resources/codex-cli"
            let manifest = "\(packageDirectory)/codex-package.json"
            if let data = FileManager.default.contents(atPath: manifest),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let entrypoint = object["entrypoint"] as? String,
               !entrypoint.isEmpty,
               !entrypoint.hasPrefix("/"),
               !entrypoint.split(separator: "/").contains("..") {
                paths.append("\(packageDirectory)/\(entrypoint)")
            }
            paths.append("\(packageDirectory)/bin/codex")
            paths.append("\(packageDirectory)/CodexCLI.app/Contents/MacOS/codex")
        }
        for directory in applicationDirectories {
            paths.append("\(directory)/ChatGPT.app/Contents/Resources/codex")
            paths.append("\(directory)/Codex.app/Contents/MacOS/codex")
            paths.append("\(directory)/Codex.app/Contents/Resources/codex")
        }
        paths += ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(homeDirectory)/.local/bin/codex", "/usr/bin/codex"]
        paths += (environment["PATH"] ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .map { "\($0)/codex" }
        return paths
    }
}

enum CommandRunner {
    static func run(
        executable: String,
        arguments: [String],
        input: String? = nil,
        timeout: TimeInterval = 25,
        currentDirectoryURL: URL? = nil,
        environmentOverrides: [String: String] = [:]
    ) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdinPipe = Pipe()
            let gate = CompletionGate()
            let stdoutCollector = DataCollector()
            let stderrCollector = DataCollector()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectoryURL
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
            for (key, value) in environmentOverrides {
                environment[key] = value
            }
            process.environment = environment

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                stdoutCollector.append(handle.availableData)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                stderrCollector.append(handle.availableData)
            }

            let timeoutWork = DispatchWorkItem {
                guard gate.claim() else { return }
                if process.isRunning { process.terminate() }
                continuation.resume(throwing: CommandRunnerError.timedOut(URL(fileURLWithPath: executable).lastPathComponent))
            }

            process.terminationHandler = { finishedProcess in
                guard gate.claim() else { return }
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                stdoutCollector.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                stderrCollector.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
                continuation.resume(returning: CommandResult(
                    stdout: String(decoding: stdoutCollector.data, as: UTF8.self),
                    stderr: String(decoding: stderrCollector.data, as: UTF8.self),
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

private final class DataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
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
