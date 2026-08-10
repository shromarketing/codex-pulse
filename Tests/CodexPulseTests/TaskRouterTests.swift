#if canImport(XCTest)
import XCTest
@testable import CodexPulse

final class TaskRouterTests: XCTestCase {
    func testSmallTaskUsesEconomicalRoute() {
        let recommendation = TaskRouter().recommend(
            task: "Исправь опечатку в README",
            codex: connected(.codex, remaining: 70),
            claude: .unavailable(.claude, message: "Not connected")
        )

        XCTAssertEqual(recommendation.model.rawValue, "Luna")
        XCTAssertEqual(recommendation.effort.rawValue, "low")
        XCTAssertEqual(recommendation.provider.rawValue, "codex")
    }

    func testArchitectureTaskUsesDeepRoute() {
        let recommendation = TaskRouter().recommend(
            task: "Проведи архитектурный рефакторинг и проверку безопасности",
            codex: connected(.codex, remaining: 60),
            claude: connected(.claude, remaining: 80)
        )

        XCTAssertEqual(recommendation.model.rawValue, "Sol")
        XCTAssertEqual(recommendation.effort.rawValue, "high")
        XCTAssertEqual(recommendation.estimate.rawValue, "high")
    }

    func testWritingPrefersConnectedClaudeWithinQuotaTolerance() {
        let recommendation = TaskRouter().recommend(
            task: "Rewrite this article and improve the strategy",
            codex: connected(.codex, remaining: 72),
            claude: connected(.claude, remaining: 65)
        )

        XCTAssertEqual(recommendation.provider.rawValue, "claude")
    }

    func testQuotaRemainingIsClamped() {
        XCTAssertEqual(QuotaWindow(usedPercent: -10, resetsAt: nil, windowMinutes: nil).remainingPercent, 100)
        XCTAssertEqual(QuotaWindow(usedPercent: 130, resetsAt: nil, windowMinutes: nil).remainingPercent, 0)
    }

    private func connected(_ provider: ProviderKind, remaining: Double) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: provider,
            state: .connected,
            quota: QuotaWindow(usedPercent: 100 - remaining, resetsAt: nil, windowMinutes: 10_080),
            source: "test",
            message: nil,
            updatedAt: .now,
            history: []
        )
    }
}
#endif
