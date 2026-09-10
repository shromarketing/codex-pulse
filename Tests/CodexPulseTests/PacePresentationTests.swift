import Foundation
import Testing
@testable import CodexPulse

@Suite("Quota timing and forecast copy")
struct PacePresentationTests {
    @Test("Reset copy names the event instead of showing an ambiguous duration")
    func resetCopyNamesTheEvent() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = now.addingTimeInterval((4 * 86_400) + (22 * 3_600))

        #expect(quotaResetText(reset, language: .russian, now: now) == "Лимит обновится через 4 д 22 ч")
        #expect(quotaResetText(reset, language: .english, now: now) == "Limit resets in 4d 22h")
        #expect(quotaResetText(reset, language: .russian, now: now, compact: true) == "Сброс через 4 д 22 ч")
    }

    @Test("Compact widget keeps the weekly reset visible")
    func compactWidgetKeepsWeeklyResetVisible() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = now.addingTimeInterval((4 * 86_400) + (22 * 3_600))

        #expect(weeklyQuotaResetText(reset, language: .russian, now: now) == "Недельный лимит обновится через 4 д 22 ч")
        #expect(weeklyQuotaResetText(reset, language: .english, now: now) == "Weekly limit resets in 4d 22h")
    }

    @Test("Claude session copy identifies the five-hour window")
    func sessionResetCopyNamesSession() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = now.addingTimeInterval((4 * 3_600) + (36 * 60))

        #expect(sessionQuotaResetText(reset, language: .russian, now: now) == "Лимит сессии обновится через 4 ч 36 мин")
        #expect(sessionQuotaResetText(reset, language: .english, now: now) == "Session limit resets in 4h 36m")
    }

    @Test("Forecast distinguishes exhaustion from reset")
    func forecastDistinguishesExhaustionFromReset() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = now.addingTimeInterval(5 * 86_400)
        let exhaustion = now.addingTimeInterval((16 * 3_600) + (39 * 60))
        let insight = PaceInsight(
            level: .watch,
            burnPercentPerDay: 36,
            safePercentToday: 5,
            projectedExhaustion: exhaustion,
            resetAt: reset
        )

        #expect(quotaForecastText(insight, language: .russian, now: now) == "При текущем темпе закончится через 16 ч 39 мин")
        #expect(quotaForecastText(insight, language: .english, now: now, compact: true) == "Runs out in 16h 39m")
    }

    @Test("Healthy forecast says the quota should last until reset")
    func healthyForecastSaysQuotaShouldLast() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = now.addingTimeInterval(2 * 86_400)
        let insight = PaceInsight(
            level: .healthy,
            burnPercentPerDay: 5,
            safePercentToday: 20,
            projectedExhaustion: reset.addingTimeInterval(86_400),
            resetAt: reset
        )

        #expect(quotaForecastText(insight, language: .russian, now: now, compact: true) == "Хватит до сброса")
    }

    @Test("Pace engine calculates exhaustion from the supplied clock")
    func paceEngineUsesSuppliedClock() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = ProviderSnapshot(
            provider: .codex,
            state: .connected,
            quota: QuotaWindow(usedPercent: 75, resetsAt: now.addingTimeInterval(5 * 86_400), windowMinutes: 10_080),
            source: "test",
            message: nil,
            updatedAt: now,
            history: []
        )
        let history = [
            UsagePoint(date: now.addingTimeInterval(-2 * 86_400), provider: .codex, usedPercent: 55),
            UsagePoint(date: now, provider: .codex, usedPercent: 75),
        ]

        let insight = PaceEngine().insight(for: snapshot, history: history, now: now)
        let exhaustion = try #require(insight.projectedExhaustion)

        #expect(insight.level == .watch)
        #expect(insight.burnPercentPerDay == 10)
        #expect(insight.safePercentToday == 5)
        #expect(abs(exhaustion.timeIntervalSince(now) - (2.5 * 86_400)) < 0.1)
    }
}
