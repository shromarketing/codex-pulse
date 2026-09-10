import Foundation
import Testing
@testable import CodexPulse

@Suite("Usage analytics")
struct AnalyticsModelsTests {
    @Test("Local Claude Code metadata produces model and project aggregates without message text")
    func localClaudeCodeMetadataProducesUsageBreakdowns() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-pulse-claude-analytics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = directory.appendingPathComponent("session.jsonl")
        let records = [
            """
            {"type":"assistant","timestamp":"2026-09-08T08:00:00.000Z","cwd":"/work/ClaudeSite","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":120,"cache_read_input_tokens":30,"cache_creation_input_tokens":20,"output_tokens":40}}}
            """,
            """
            {"type":"user","timestamp":"2026-09-08T08:01:00.000Z","message":{"content":"private prompt that must never affect analytics"}}
            """,
            """
            {"type":"assistant","timestamp":"2026-09-08T09:00:00.000Z","cwd":"/work/Client","message":{"model":"claude-opus-4-6","usage":{"input_tokens":50,"output_tokens":10}}}
            """,
        ]
        try records.joined(separator: "\n").write(to: session, atomically: true, encoding: .utf8)

        let scanner = ClaudeCodeSessionAnalyticsScanner(sessionRoots: [directory])
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-08T12:00:00Z"))
        let snapshot = try #require(await scanner.fetch(days: 30, now: now))

        #expect(snapshot.provider == .claude)
        #expect(snapshot.totals.totalTokens == 270)
        #expect(snapshot.totals.inputTokens == 190)
        #expect(snapshot.totals.cacheReadTokens == 30)
        #expect(snapshot.projects.map(\.name).sorted() == ["ClaudeSite", "Client"])
        #expect(snapshot.modelTotals.map(\.modelName).sorted() == ["claude-opus-4-6", "claude-sonnet-4-6"])
        #expect(snapshot.totals.totalCost == nil)
    }

    @Test("Local Codex metadata produces model and project aggregates without message text")
    func localCodexMetadataProducesUsageBreakdowns() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-pulse-analytics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let solSession = directory.appendingPathComponent("sol-rollout.jsonl")
        let solRecords = [
            """
            {"type":"session_meta","timestamp":"2026-09-08T08:00:00.000Z","payload":{"cwd":"/work/Pulse","base_instructions":{"provenance":{"model":"gpt-5.6-sol"}}}}
            """,
            """
            {"type":"response_item","timestamp":"2026-09-08T08:01:00.000Z","payload":{"content":"a private prompt that must never affect analytics"}}
            """,
            """
            {"type":"token_usage_record","timestamp":"2026-09-08T08:02:00.000Z","payload":{"usage":{"input_tokens":120,"cached_input_tokens":20,"output_tokens":30,"total_tokens":150}}}
            """,
        ]
        let terraSession = directory.appendingPathComponent("terra-rollout.jsonl")
        let terraRecords = [
            """
            {"type":"turn_context","timestamp":"2026-09-08T09:00:00.000Z","payload":{"cwd":"/work/Client","model":"gpt-5.6-terra"}}
            """,
            """
            {"type":"token_usage_record","timestamp":"2026-09-08T09:01:00.000Z","payload":{"usage":{"input_tokens":50,"cached_input_tokens":0,"output_tokens":10,"total_tokens":60}}}
            """,
            """
            {"type":"token_usage_record","timestamp":"2026-05-01T09:01:00.000Z","payload":{"usage":{"input_tokens":900,"cached_input_tokens":0,"output_tokens":0,"total_tokens":900}}}
            """,
        ]
        try solRecords.joined(separator: "\n").write(to: solSession, atomically: true, encoding: .utf8)
        try terraRecords.joined(separator: "\n").write(to: terraSession, atomically: true, encoding: .utf8)

        let scanner = CodexSessionAnalyticsScanner(sessionRoots: [directory])
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-08T12:00:00Z"))
        let snapshot = try #require(await scanner.fetch(days: 30, now: now))

        #expect(snapshot.totals.totalTokens == 210)
        #expect(snapshot.totals.inputTokens == 170)
        #expect(snapshot.totals.cacheReadTokens == 20)
        #expect(snapshot.projects.map(\.name).sorted() == ["Client", "Pulse"])
        #expect(snapshot.modelTotals.map(\.modelName).sorted() == ["gpt-5.6-sol", "gpt-5.6-terra"])
        #expect(snapshot.modelTotals.first { $0.modelName == "gpt-5.6-sol" }?.totalTokens == 150)
        #expect(snapshot.totals.totalCost == nil)
    }

    @Test("Filtering uses an inclusive local window and recalculates breakdowns")
    func filteringUsesInclusiveLocalWindowAndRecalculatesBreakdowns() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 12)))
        let snapshot = UsageAnalyticsSnapshot(
            provider: .codex,
            currencyCode: "USD",
            source: "test",
            updatedAt: now,
            totals: totals(tokens: 60, cost: 6),
            daily: [
                day("2026-08-04", tokens: 10, cost: 1, model: "Luna"),
                day("2026-08-05", tokens: 20, cost: 2, model: "Terra"),
                day("2026-08-11", tokens: 30, cost: 3, model: "Terra"),
            ],
            projects: [
                ProjectUsage(
                    name: "Pulse",
                    path: "/Pulse",
                    totalTokens: 60,
                    totalCost: 6,
                    modelBreakdowns: [],
                    daily: [
                        day("2026-08-04", tokens: 10, cost: 1, model: "Luna"),
                        day("2026-08-05", tokens: 20, cost: 2, model: "Terra"),
                        day("2026-08-11", tokens: 30, cost: 3, model: "Terra"),
                    ]
                ),
            ],
            accountSummary: .empty,
            accountDaily: [
                AccountDailyUsage(startDate: "2026-08-04", tokens: 10),
                AccountDailyUsage(startDate: "2026-08-05", tokens: 20),
                AccountDailyUsage(startDate: "2026-08-11", tokens: 30),
            ]
        )

        let filtered = snapshot.filtered(to: .week, now: now, calendar: calendar)
        let project = try #require(filtered.projects.first)
        let primaryModel = try #require(project.modelBreakdowns.first)

        #expect(filtered.daily.map(\.date) == ["2026-08-05", "2026-08-11"])
        #expect(filtered.totals.totalTokens == 50)
        #expect(filtered.totals.totalCost == 5)
        #expect(project.totalTokens == 50)
        #expect(primaryModel.modelName == "Terra")
        #expect(primaryModel.totalTokens == 50)
        #expect(filtered.accountDaily.map(\.startDate) == ["2026-08-05", "2026-08-11"])
    }

    @Test("Model insights keep local token shares separate from quota and identify the main project")
    func modelInsightsExposeShareCoverageAndMainProject() {
        let snapshot = UsageAnalyticsSnapshot(
            provider: .codex,
            currencyCode: "USD",
            source: "test",
            updatedAt: .now,
            totals: totals(tokens: 120, cost: 12),
            daily: [
                DailyTokenUsage(
                    date: "2026-09-08",
                    inputTokens: 0,
                    cacheReadTokens: 0,
                    outputTokens: 0,
                    totalTokens: 120,
                    totalCost: 12,
                    modelBreakdowns: [
                        ModelUsage(modelName: "Terra", totalTokens: 60, cost: 6),
                        ModelUsage(modelName: "Sol", totalTokens: 30, cost: 3),
                    ]
                ),
            ],
            projects: [
                ProjectUsage(name: "Pulse", path: "/Pulse", totalTokens: 80, totalCost: 8, modelBreakdowns: [ModelUsage(modelName: "Terra", totalTokens: 50, cost: 5)], daily: []),
                ProjectUsage(name: "Client", path: "/Client", totalTokens: 40, totalCost: 4, modelBreakdowns: [ModelUsage(modelName: "Terra", totalTokens: 10, cost: 1), ModelUsage(modelName: "Sol", totalTokens: 30, cost: 3)], daily: []),
            ],
            accountSummary: .empty,
            accountDaily: []
        )

        let breakdown = snapshot.modelUsageBreakdown
        let terra = breakdown.insights.first { $0.modelName == "Terra" }

        #expect(breakdown.attributedTokens == 90)
        #expect(breakdown.coverage == 0.75)
        #expect(terra?.shareOfAttributedTokens == 2.0 / 3.0)
        #expect(terra?.topProjectName == "Pulse")
        #expect(terra?.topProjectTokens == 50)
    }

    private func totals(tokens: Int64, cost: Double) -> TokenTotals {
        TokenTotals(inputTokens: tokens, cacheReadTokens: 0, outputTokens: 0, totalTokens: tokens, totalCost: cost)
    }

    private func day(_ date: String, tokens: Int64, cost: Double, model: String) -> DailyTokenUsage {
        DailyTokenUsage(
            date: date,
            inputTokens: tokens,
            cacheReadTokens: 0,
            outputTokens: 0,
            totalTokens: tokens,
            totalCost: cost,
            modelBreakdowns: [ModelUsage(modelName: model, totalTokens: tokens, cost: cost)]
        )
    }
}
