import Foundation

/// Builds token analytics from Codex's local *metadata* records. The decoder
/// intentionally has no fields for chat messages or prompt content.
actor CodexSessionAnalyticsScanner {
    private let fileManager: FileManager
    private let sessionRoots: [URL]
    private var cachedFiles: [URL: CachedFile] = [:]

    init(
        fileManager: FileManager = .default,
        sessionRoots: [URL] = [
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/archived_sessions"),
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

        var samples: [CodexSessionUsageSample] = []
        for file in files {
            if let cached = cachedFiles[file.url], cached.stamp == file.stamp {
                samples += cached.samples
                continue
            }

            let parsed = readUsageSamples(from: file.url)
            cachedFiles[file.url] = CachedFile(stamp: file.stamp, samples: parsed)
            samples += parsed
        }

        return CodexSessionAnalyticsParser.snapshot(samples: samples, cutoff: cutoff, now: now, calendar: calendar)
    }

    private func sessionFiles(modifiedSince cutoff: Date) -> [SessionFile] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        var result: [SessionFile] = []
        for root in sessionRoots {
            guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: Array(keys)) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl",
                      let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      let modifiedAt = values.contentModificationDate,
                      modifiedAt >= cutoff
                else { continue }
                result.append(SessionFile(
                    url: url,
                    stamp: FileStamp(modifiedAt: modifiedAt, size: Int64(values.fileSize ?? 0))
                ))
            }
        }
        return result.sorted { $0.url.path < $1.url.path }
    }

    private func readUsageSamples(from url: URL) -> [CodexSessionUsageSample] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        var context = CodexSessionContext()
        var latest: CodexSessionUsageSample?
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: 0)

        // Session totals are cumulative. Reading the header and tail is enough
        // to get the latest total, model and working folder without decoding
        // gigabytes of historical conversation records on every refresh.
        readSegment(
            handle: handle,
            byteCount: min(size, 128 * 1024),
            discardFirstPartialLine: false,
            context: &context,
            latest: &latest
        )
        if size > 128 * 1024 {
            let tailOffset = size - min(size, 192 * 1024)
            try? handle.seek(toOffset: tailOffset)
            readSegment(
                handle: handle,
                byteCount: min(size, 192 * 1024),
                discardFirstPartialLine: true,
                context: &context,
                latest: &latest
            )
        }
        return latest.map { [$0] } ?? []
    }

    private func readSegment(
        handle: FileHandle,
        byteCount: UInt64,
        discardFirstPartialLine: Bool,
        context: inout CodexSessionContext,
        latest: inout CodexSessionUsageSample?
    ) {
        var remaining = byteCount
        var buffer = Data()
        var shouldDiscardFirstLine = discardFirstPartialLine
        while remaining > 0,
              let chunk = try? handle.read(upToCount: Int(min(UInt64(64 * 1024), remaining))),
              !chunk.isEmpty {
            remaining -= UInt64(chunk.count)
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if shouldDiscardFirstLine {
                    shouldDiscardFirstLine = false
                    continue
                }
                parse(line: line, context: &context, latest: &latest)
            }
        }
        if !buffer.isEmpty, !shouldDiscardFirstLine {
            parse(line: buffer, context: &context, latest: &latest)
        }
    }

    private func parse(
        line: Data,
        context: inout CodexSessionContext,
        latest: inout CodexSessionUsageSample?
    ) {
        // Oversized records are usually rich conversation payloads, never a
        // token record. Skipping them protects refresh responsiveness.
        guard line.count <= 1_000_000,
              let record = try? JSONDecoder().decode(CodexSessionRecord.self, from: line)
        else { return }

        context.apply(record.payload?.context)
        guard record.type == "token_usage_record",
              let usage = record.payload?.threadTokenUsage ?? record.payload?.usage,
              let total = usage.totalTokens,
              total > 0,
              let date = CodexSessionRecord.date(from: record.timestamp)
        else { return }

        let sample = CodexSessionUsageSample(
            date: date,
            model: context.model ?? "Неизвестная модель",
            projectPath: context.cwd ?? "",
            inputTokens: usage.inputTokens ?? 0,
            cachedInputTokens: usage.cachedInputTokens ?? 0,
            outputTokens: usage.outputTokens ?? 0,
            totalTokens: total
        )
        if (latest?.date ?? .distantPast) <= sample.date {
            latest = sample
        }
    }
}

private struct SessionFile {
    let url: URL
    let stamp: FileStamp
}

private struct FileStamp: Equatable {
    let modifiedAt: Date
    let size: Int64
}

private struct CachedFile {
    let stamp: FileStamp
    let samples: [CodexSessionUsageSample]
}

struct CodexSessionUsageSample: Sendable {
    let date: Date
    let model: String
    let projectPath: String
    let inputTokens: Int64
    let cachedInputTokens: Int64
    let outputTokens: Int64
    let totalTokens: Int64
}

private struct CodexSessionContext {
    var model: String?
    var cwd: String?

    mutating func apply(_ context: CodexSessionRecord.Context?) {
        guard let context else { return }
        if let model = context.model, !model.isEmpty { self.model = model }
        if let cwd = context.cwd, !cwd.isEmpty { self.cwd = cwd }
    }
}

/// The schema has deliberately narrow coding keys. Unknown JSON, including
/// conversation content, is skipped by `Decodable` and never retained.
private struct CodexSessionRecord: Decodable {
    let type: String
    let timestamp: String
    let payload: Payload?

    struct Payload: Decodable {
        let model: String?
        let cwd: String?
        let usage: Usage?
        let threadTokenUsage: Usage?
        let threadSettings: Context?
        let collaborationMode: CollaborationMode?
        let baseInstructions: BaseInstructions?
        let state: WorldState?

        enum CodingKeys: String, CodingKey {
            case model, cwd, usage
            case threadTokenUsage = "thread_token_usage"
            case threadSettings = "thread_settings"
            case collaborationMode = "collaboration_mode"
            case baseInstructions = "base_instructions"
            case state
        }

        var context: Context? {
            let candidates = [
                Context(model: model, cwd: cwd),
                threadSettings,
                collaborationMode?.settings,
                baseInstructions?.provenance,
                state?.context,
            ]
            let model = candidates.compactMap { $0?.model }.first
            let cwd = candidates.compactMap { $0?.cwd }.first
            guard model != nil || cwd != nil else { return nil }
            return Context(model: model, cwd: cwd)
        }
    }

    struct Context: Decodable {
        let model: String?
        let cwd: String?
    }

    struct CollaborationMode: Decodable {
        let settings: Context?
    }

    struct BaseInstructions: Decodable {
        let provenance: Context?
    }

    struct WorldState: Decodable {
        let model: String?
        let collaborationMode: CollaborationMode?
        let environments: Environments?

        enum CodingKeys: String, CodingKey {
            case model, environments
            case collaborationMode = "collaboration_mode"
        }

        var context: Context {
            Context(model: model ?? collaborationMode?.settings?.model, cwd: environments?.local?.cwd)
        }
    }

    struct Environments: Decodable {
        let local: Context?
    }

    struct Usage: Decodable {
        let inputTokens: Int64?
        let cachedInputTokens: Int64?
        let outputTokens: Int64?
        let totalTokens: Int64?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case cachedInputTokens = "cached_input_tokens"
            case outputTokens = "output_tokens"
            case totalTokens = "total_tokens"
        }
    }

    static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private enum CodexSessionAnalyticsParser {
    static func snapshot(
        samples: [CodexSessionUsageSample],
        cutoff: Date,
        now: Date,
        calendar: Calendar
    ) -> UsageAnalyticsSnapshot? {
        let relevant = samples.filter { $0.date >= cutoff }
        guard !relevant.isEmpty else { return nil }

        var days: [String: DayAccumulator] = [:]
        var projects: [String: ProjectAccumulator] = [:]
        for sample in relevant {
            let day = dayKey(for: sample.date, calendar: calendar)
            days[day, default: DayAccumulator()].add(sample)
            let path = sample.projectPath
            projects[path, default: ProjectAccumulator(path: path)].add(sample, day: day)
        }

        let daily = days.keys.sorted().map { day in days[day, default: DayAccumulator()].usage(date: day) }
        let projectUsage = projects.values
            .map(\.usage)
            .sorted { $0.totalTokens > $1.totalTokens }
        let totals = TokenTotals(
            inputTokens: daily.reduce(0) { $0 + $1.inputTokens },
            cacheReadTokens: daily.reduce(0) { $0 + $1.cacheReadTokens },
            outputTokens: daily.reduce(0) { $0 + $1.outputTokens },
            totalTokens: daily.reduce(0) { $0 + $1.totalTokens },
            totalCost: nil
        )

        return UsageAnalyticsSnapshot(
            provider: .codex,
            currencyCode: "USD",
            source: "Codex local session metadata",
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

private struct DayAccumulator {
    var inputTokens: Int64 = 0
    var cachedInputTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var totalTokens: Int64 = 0
    var models: [String: Int64] = [:]

    mutating func add(_ sample: CodexSessionUsageSample) {
        inputTokens += sample.inputTokens
        cachedInputTokens += sample.cachedInputTokens
        outputTokens += sample.outputTokens
        totalTokens += sample.totalTokens
        models[sample.model, default: 0] += sample.totalTokens
    }

    func usage(date: String) -> DailyTokenUsage {
        DailyTokenUsage(
            date: date,
            inputTokens: inputTokens,
            cacheReadTokens: cachedInputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            totalCost: nil,
            modelBreakdowns: models.map { ModelUsage(modelName: $0.key, totalTokens: $0.value, cost: nil) }
                .sorted { $0.totalTokens > $1.totalTokens }
        )
    }
}

private struct ProjectAccumulator {
    let path: String
    var days: [String: DayAccumulator] = [:]

    init(path: String) {
        self.path = path
    }

    mutating func add(_ sample: CodexSessionUsageSample, day: String) {
        days[day, default: DayAccumulator()].add(sample)
    }

    var usage: ProjectUsage {
        let daily = days.keys.sorted().map { day in days[day, default: DayAccumulator()].usage(date: day) }
        let totals = TokenTotals(
            inputTokens: daily.reduce(0) { $0 + $1.inputTokens },
            cacheReadTokens: daily.reduce(0) { $0 + $1.cacheReadTokens },
            outputTokens: daily.reduce(0) { $0 + $1.outputTokens },
            totalTokens: daily.reduce(0) { $0 + $1.totalTokens },
            totalCost: nil
        )
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
