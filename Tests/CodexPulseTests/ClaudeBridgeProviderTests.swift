import Foundation
import Testing
@testable import CodexPulse

@Suite("Claude Web provider bridge")
struct ClaudeBridgeProviderTests {
    @Test("Parses session, weekly, and model-specific quota windows")
    func parsesEveryClaudeQuotaWindow() throws {
        let payload = """
        [{
          "provider": "claude",
          "source": "web",
          "usage": {
            "primary": {
              "usedPercent": 12,
              "windowMinutes": 300,
              "resetsAt": "2026-08-11T18:36:00Z"
            },
            "secondary": {
              "usedPercent": 66,
              "windowMinutes": 10080,
              "resetsAt": "2026-08-11T17:16:00Z"
            },
            "tertiary": null,
            "extraRateWindows": [{
              "id": "claude-weekly-scoped-fable",
              "title": "Fable",
              "usageKnown": true,
              "window": {
                "usedPercent": 74,
                "windowMinutes": 10080,
                "resetsAt": "2026-08-11T17:16:00.000Z"
              }
            }],
            "updatedAt": "2026-08-11T14:00:00Z",
            "identity": { "loginMethod": "Claude Max 5x" }
          },
          "credits": { "remaining": 125.5 }
        }]
        """

        let result = CodexBarBridgeProvider.parseClaudePayload(
            try #require(payload.data(using: .utf8)),
            requestedSource: .web
        )

        #expect(result.snapshot.state == .connected)
        #expect(result.snapshot.remainingPercent == 26)
        #expect(result.snapshot.source == "Claude Web via local bridge")
        #expect(result.accountDetails.planName == "Claude Max 5x")
        #expect(result.accountDetails.creditBalance == "125.50")
        #expect(result.accountDetails.quotaMeters.count == 3)
        #expect(result.accountDetails.quotaMeters[0].scope == .session)
        #expect(result.accountDetails.quotaMeters[0].window.remainingPercent == 88)
        #expect(result.accountDetails.quotaMeters[1].scope == .weekly)
        #expect(result.accountDetails.quotaMeters[1].window.remainingPercent == 34)
        #expect(result.accountDetails.quotaMeters[2].providerTitle == "Fable")
        #expect(result.accountDetails.quotaMeters[2].window.remainingPercent == 26)
    }

    @Test("Does not turn a reset-only placeholder into an exhausted quota")
    func ignoresSyntheticPlaceholder() throws {
        let payload = """
        [{
          "provider": "claude",
          "source": "web",
          "usage": {
            "primary": {
              "usedPercent": 100,
              "windowMinutes": 300,
              "isSyntheticPlaceholder": true
            },
            "secondary": {
              "usedPercent": 25,
              "windowMinutes": 10080,
              "resetsAt": "2026-08-18T10:00:00Z"
            }
          }
        }]
        """

        let result = CodexBarBridgeProvider.parseClaudePayload(
            try #require(payload.data(using: .utf8)),
            requestedSource: .web
        )

        #expect(result.snapshot.state == .connected)
        #expect(result.snapshot.remainingPercent == 75)
        #expect(result.accountDetails.quotaMeters.first?.usageKnown == false)
        #expect(claudeQuotaMeters(result.accountDetails, language: .russian).count == 1)
    }

    @Test("Returns a recoverable disconnected state for missing browser session")
    func handlesMissingBrowserSession() throws {
        let payload = """
        [{"provider":"claude","source":"web","error":{"kind":"provider","message":"No Claude session key found in browser cookies."}}]
        """

        let result = CodexBarBridgeProvider.parseClaudePayload(
            try #require(payload.data(using: .utf8)),
            requestedSource: .web
        )

        #expect(result.snapshot.state == .unavailable)
        #expect(result.snapshot.message?.contains("session key") == true)
        #expect(result.accountDetails == .empty)
    }
}
