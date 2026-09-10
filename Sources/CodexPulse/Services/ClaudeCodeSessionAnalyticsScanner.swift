import Foundation

/// Builds usage analytics from Claude Code's local session *metadata*.
/// The narrow decoder intentionally has no fields for prompts or replies.
actor ClaudeCodeSessionAnalyticsScanner {
    private let fileManager: FileManager
    private let sessionRoots: [URL]
    private var cachedFiles: [URL: CachedClaudeFile] = [:]

    init(
        fileManager: FileManager = .default,
        sessionRoots: [URL] = [
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Claude/claude-code-sessions"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions"),
        ]
    ) {
        self.fileManager = fileManager
        self.sessionRoots = sessionRoots
    }

    func fetch(days: Int, now: Date = .now) -> UsageAnalyticsSnapshot? {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: calendar.startOfDay(for: now)) else {
            return nil
        }

        let files = sessionFiles(modifiedSince: cutoff)
        let activeURLs = Set(files.map(\.url))
        cachedFiles = cachedFiles.filter { activeURLs.contains($0.key) }

        var samples: [ClaudeCodeUsageSample] = []
        for file in files {
            if let cached = cachedFiles[file.url], cached.stamp == file.stamp {
                samples += cached.samples
                continue
            }
            let parsed = readUsageSamples(from: file.url)
            cachedFiles[file.url] = CachedClaudeFile(stamp: file.stamp, samples: parsed)
            samples += parsed
        }

        return ClaudeCodeSessionAnalyticsParser.snapshot(samples: samples, cutoff: cutoff, now: now, calendar: calendar)
    }

    private func sessionFiles(modifiedSince cutoff: Date) -> [ClaudeSessionFile] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        var result: [ClaudeSessionFile] = []
        for root in sessionRoots {
            guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: Array(keys)) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl",
                      let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      let modifiedAt = values.contentModificationDate,
                      modifiedAt >= cutoff
                else { continue }
                result.append(ClaudeSessionFile(
                    url: url,
                    stamp: ClaudeFileStamp(modifiedAt: modifiedAt, size: Int64(values.fileSize ?? 0))
                ))
            }
        }
        return result.sorted { $0.url.path < $1.url.path }
    }

    private func readUsageSamples(from url: URL) -> [ClaudeCodeUsageSample] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        // Claude's per-turn usage is not cumulative. Stream the JSONL file,
        // cache it by modification stamp, and retain only numeric metadata.
        var samples: [ClaudeCodeUsageSample] = []
        var buffer = Data()
        while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                parse(line: line, into: &samples)
            }
        }
        if !buffer.isEmpty { parse(line: buffer, into: &samples) }
        return samples
    }

    private func parse(line: Data, into samples: inout [ClaudeCodeUsageSample]) {
        // Oversized records typically hold rich content, never the small
        // accounting payload we need. Skipping them keeps refresh responsive.
        guard line.count <= 1_000_000,
              let record = try? JSONDecoder().decode(ClaudeCodeSessionRecord.self, from: line),
              record.type == "assistant",
              let date = ClaudeCodeSessionRecord.date(from: record.timestamp),
              let usage = record.message?.usage ?? record.usage
        else { return }

        let input = usage.inputTokens ?? 0
        let cacheRead = usage.cacheReadInputTokens ?? 0
        let cacheCreation = usage.cacheCreationInputTokens ?? 0
        let output = usage.outputTokens ?? 0
        let total = input + cacheRead + cacheCreation + output
        guard total > 0 else { return }

        samples.append(ClaudeCodeUsageSample(
            date: date,
            model: record.message?.model ?? record.model ?? "Неизвестная модель",
            projectPath: record.cwd ?? "",
            inputTokens: input + cacheCreation,
            cacheReadTokens: cacheRead,
            outputTokens: output,
            totalTokens: total
        ))
    }
}

private struct ClaudeSessionFile {
    let url: URL
    let stamp: ClaudeFileStamp
}

private struct ClaudeFileStamp: Equatable {
    let modifiedAt: Date
    let size: Int64
}

private struct CachedClaudeFile {
    let stamp: ClaudeFileStamp
    let samples: [ClaudeCodeUsageSample]
}

struct ClaudeCodeUsageSample: Sendable {
    let date: Date
    let model: String
    let projectPath: String
    let inputTokens: Int64
    let cacheReadTokens: Int64
    let outputTokens: Int64
    let totalTokens: Int64
}

/// Unknown JSON keys are deliberately ignored. In particular, `content` is
/// not represented here and is never retained by the scanner.
private struct ClaudeCodeSessionRecord: Decodable {
    let type: String?
    let timestamp: String?
    let cwd: String?
    let model: String?
    let usage: Usage?
    let message: Message?

    struct Message: Decodable {
        let model: String?
        let usage: Usage?
    }

    struct Usage: Decodable {
        let inputTokens: Int64?
        let cacheReadInputTokens: Int64?
        let cacheCreationInputTokens: Int64?
        let outputTokens: Int64?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private enum ClaudeCodeSessionAnalyticsParser {
    static func snapshot(
        samples: [ClaudeCodeUsageSample],
        cutoff: Date,
        now: Date,
        calendar: Calendar
    ) -> UsageAnalyticsSnapshot? {
        let relevant = samples.filter { $0.date >= cutoff }
        guard !relevant.isEmpty else { return nil }

        var days: [String: ClaudeDayAccumulator] = [:]
        var projects: [String: ClaudeProjectAccumulator] = [:]
        for sample in relevant {
            let day = dayKey(for: sample.date, calendar: calendar)
            days[day, default: ClaudeDayAccumulator()].add(sample)
            let path = sample.projectPath
            projects[path, default: ClaudeProjectAccumulator(path: path)].add(sample, day: day)
        }

        let daily = days.keys.sorted().map { day in days[day, default: ClaudeDayAccumulator()].usage(date: day) }
        let projectUsage = projects.values.map(\.usage).sorted { $0.totalTokens > $1.totalTokens }
        let totals = ClaudeAnalyticsTotals.from(daily)
        return UsageAnalyticsSnapshot(
            provider: .claude,
            currencyCode: "USD",
            source: "Claude Code local session metadata",
            updatedAt: now,
            totals: totals,
            daily: daily,
            projects: projectUsage,
            accountSummary: nil,
            accountDaily: []
        )
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

private struct ClaudeDayAccumulator {
    var inputTokens: Int64 = 0
    var cacheReadTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var totalTokens: Int64 = 0
    var models: [String: Int64] = [:]

    mutating func add(_ sample: ClaudeCodeUsageSample) {
        inputTokens += sample.inputTokens
        cacheReadTokens += sample.cacheReadTokens
        outputTokens += sample.outputTokens
        totalTokens += sample.totalTokens
        models[sample.model, default: 0] += sample.totalTokens
    }

    func usage(date: String) -> DailyTokenUsage {
        DailyTokenUsage(
            date: date,
            inputTokens: inputTokens,
            cacheReadTokens: cacheReadTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            totalCost: nil,
            modelBreakdowns: models.map { ModelUsage(modelName: $0.key, totalTokens: $0.value, cost: nil) }
                .sorted { $0.totalTokens > $1.totalTokens }
        )
    }
}

private struct ClaudeProjectAccumulator {
    let path: String
    var days: [String: ClaudeDayAccumulator] = [:]

    init(path: String) { self.path = path }

    mutating func add(_ sample: ClaudeCodeUsageSample, day: String) {
        days[day, default: ClaudeDayAccumulator()].add(sample)
    }

    var usage: ProjectUsage {
        let daily = days.keys.sorted().map { day in days[day, default: ClaudeDayAccumulator()].usage(date: day) }
        let totals = ClaudeAnalyticsTotals.from(daily)
        let name = path.isEmpty ? "Рабочая папка не указана" : URL(fileURLWithPath: path).lastPathComponent
        return ProjectUsage(
            name: name,
            path: path,
            totalTokens: totals.totalTokens,
            totalCost: nil,
            modelBreakdowns: daily.flatMap(\.modelBreakdowns)
                .reduce(into: [String: Int64]()) { $0[$1.modelName, default: 0] += $1.totalTokens }
                .map { ModelUsage(modelName: $0.key, totalTokens: $0.value, cost: nil) }
                .sorted { $0.totalTokens > $1.totalTokens },
            daily: daily
        )
    }
}

private enum ClaudeAnalyticsTotals {
    static func from(_ daily: [DailyTokenUsage]) -> TokenTotals {
        TokenTotals(
            inputTokens: daily.reduce(0) { $0 + $1.inputTokens },
            cacheReadTokens: daily.reduce(0) { $0 + $1.cacheReadTokens },
            outputTokens: daily.reduce(0) { $0 + $1.outputTokens },
            totalTokens: daily.reduce(0) { $0 + $1.totalTokens },
            totalCost: nil
        )
    }
}
