import Foundation
import Testing
@testable import CodexPulse

@Suite("Codex quota presentation")
struct CodexQuotaPresentationTests {
    @Test("Hides the separate Spark bucket from the everyday quota display")
    func hidesSparkBucket() {
        let window = QuotaWindow(usedPercent: 0, resetsAt: nil, windowMinutes: 10_080)
        let details = CodexAccountDetails(
            quotaBuckets: [
                CodexQuotaBucket(id: "codex", name: "Codex", planType: "pro", primary: window, secondary: nil, creditBalance: nil, hasCredits: nil, unlimitedCredits: false),
                CodexQuotaBucket(id: "codex_spark", name: "Codex Spark", planType: "pro", primary: window, secondary: window, creditBalance: nil, hasCredits: nil, unlimitedCredits: false),
            ],
            planType: "pro",
            creditBalance: nil,
            resetCreditsAvailable: 0
        )

        let meters = codexQuotaMeters(details, language: .russian)
        #expect(meters.count == 1)
        #expect(meters.first?.title == "Codex · неделя")
    }
}
