import Foundation
import Testing
@testable import CodexPulse

@Suite("Usage analytics")
struct AnalyticsModelsTests {
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
