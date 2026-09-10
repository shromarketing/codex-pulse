import Testing
@testable import CodexPulse

@Suite("Task routing")
struct TaskRouterTests {
    @Test("Small edits use the economical route")
    func smallTaskUsesEconomicalRoute() {
        let recommendation = TaskRouter().recommend(
            task: "Исправь опечатку в README",
            codex: connected(.codex, remaining: 70),
            claude: .unavailable(.claude, message: "Not connected")
        )

        #expect(recommendation.model.rawValue == "Luna")
        #expect(recommendation.effort.rawValue == "low")
        #expect(recommendation.provider.rawValue == "codex")
    }

    @Test("A small edit with a bounded verification stays economical")
    func smallEditWithVerificationStaysEconomical() {
        let recommendation = TaskRouter().recommend(
            task: "Исправить один текст в README и проверить ссылки",
            codex: connected(.codex, remaining: 70),
            claude: connected(.claude, remaining: 90)
        )

        #expect(recommendation.model == .luna)
        #expect(recommendation.effort == .low)
        #expect(recommendation.taskShape == .quick)
        #expect(recommendation.provider == .codex)
    }

    @Test("Architecture work uses a deep route")
    func architectureTaskUsesDeepRoute() {
        let recommendation = TaskRouter().recommend(
            task: "Проведи архитектурный рефакторинг и проверку безопасности",
            codex: connected(.codex, remaining: 60),
            claude: connected(.claude, remaining: 80)
        )

        #expect(recommendation.model.rawValue == "Sol")
        #expect(recommendation.effort.rawValue == "high")
        #expect(recommendation.estimate.rawValue == "high")
    }

    @Test("A full website build does not use Luna")
    func fullWebsiteBuildDoesNotUseLuna() {
        let recommendation = TaskRouter().recommend(
            task: "Создать структуру моего нового сайта и создать сам сайт",
            codex: connected(.codex, remaining: 53),
            claude: .unavailable(.claude, message: "Not connected")
        )

        #expect(recommendation.model.rawValue == "Terra")
        #expect(recommendation.effort.rawValue == "high")
        #expect(recommendation.provider.rawValue == "codex")
    }

    @Test("Writing prefers connected Claude within quota tolerance")
    func writingPrefersConnectedClaudeWithinQuotaTolerance() {
        let recommendation = TaskRouter().recommend(
            task: "Rewrite this article and improve the strategy",
            codex: connected(.codex, remaining: 72),
            claude: connected(.claude, remaining: 65)
        )

        #expect(recommendation.provider.rawValue == "claude")
    }

    @Test("Large web automation is split and planned with Terra high")
    func largeWebAutomationIsSplit() {
        let recommendation = TaskRouter().recommend(
            task: "Проанализировать 200 сайтов и скачать 8 гигов",
            codex: connected(.codex, remaining: 43),
            claude: .unavailable(.claude, message: "Not connected")
        )

        #expect(recommendation.model == .terra)
        #expect(recommendation.effort == .high)
        #expect(recommendation.taskShape == .automation)
        #expect(recommendation.needsSplit)
        #expect(recommendation.stages.count == 3)
        #expect(recommendation.stages[1].model == .luna)
    }

    @Test("AI cannot downgrade a large external batch below the safe floor")
    func aiCannotDowngradeLargeBatch() {
        let assessment = CodexRouteAssessment(
            model: .luna,
            effort: .low,
            confidence: .high,
            taskShape: .automation,
            needsSplit: false,
            rationaleRU: "Повторяемая задача.",
            rationaleEN: "Repeatable task.",
            stages: []
        )
        let recommendation = TaskRouter().recommend(
            task: "Проанализировать 200 сайтов и скачать 8 гигабайт",
            assessment: assessment,
            codex: connected(.codex, remaining: 43),
            claude: .unavailable(.claude, message: "Not connected")
        )

        #expect(recommendation.model == .terra)
        #expect(recommendation.effort == .high)
        #expect(recommendation.needsSplit)
        #expect(recommendation.source == .codexAI)
        #expect(recommendation.stages.count == 3)
    }

    @Test("Structured Codex response is decoded without surrounding log noise")
    func structuredCodexResponseIsDecoded() throws {
        let result = try #require(CodexTaskRouteAdvisor.decodeForTesting("""
        status line
        {"model":"Terra","effort":"high","confidence":"high","task_shape":"automation","needs_split":true,"rationale_ru":"Нужен план.","rationale_en":"Needs a plan.","stages":[{"model":"Terra","effort":"high","title_ru":"План","title_en":"Plan"},{"model":"Luna","effort":"low","title_ru":"Пакет","title_en":"Batch"}]}
        """))

        #expect(result.model == .terra)
        #expect(result.effort == .high)
        #expect(result.needsSplit)
        #expect(result.stages.count == 2)
    }

    @Test("Malformed Codex response is rejected")
    func malformedCodexResponseIsRejected() {
        #expect(CodexTaskRouteAdvisor.decodeForTesting("not json") == nil)
    }

    @Test("Quota remaining is clamped", arguments: [
        (used: -10.0, expected: 100.0),
        (used: 130.0, expected: 0.0),
    ])
    func quotaRemainingIsClamped(used: Double, expected: Double) {
        #expect(QuotaWindow(usedPercent: used, resetsAt: nil, windowMinutes: nil).remainingPercent == expected)
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
