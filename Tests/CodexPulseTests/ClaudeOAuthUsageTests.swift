import Foundation
import Testing
@testable import CodexPulse

@Suite("Claude OAuth quota")
struct ClaudeOAuthUsageTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Parses account and model windows on percentage and fractional scales")
    func parsesBothScales() throws {
        for (session, week, model, expected) in [(12.0, 45.0, 33.0, 12.0), (0.12, 0.45, 0.33, 12.0)] {
            let payload = try JSONSerialization.data(withJSONObject: [
                "five_hour": ["utilization": session, "resets_at": "2027-01-01T00:00:00Z"],
                "seven_day": ["utilization": week, "resets_at": "2027-01-02T00:00:00Z"],
                "limits": [["kind": "weekly_scoped", "group": "weekly", "percent": model,
                            "scope": ["model": ["id": "claude-fable", "display_name": "Fable"]],
                            "resets_at": "2027-01-02T00:00:00Z"]],
                "seven_day_fable": ["utilization": model, "resets_at": "2027-01-02T00:00:00Z"]
            ])
            let parsed = try #require(ClaudeOAuthParser.usage(payload, capturedAt: now))
            #expect(parsed.accountDetails.quotaMeters.count == 3)
            #expect(parsed.accountDetails.quotaMeters.first?.window.usedPercent == expected)
            #expect(parsed.accountDetails.quotaMeters.last?.providerTitle == "Fable")
        }
        let mixed = try JSONSerialization.data(withJSONObject: [
            "five_hour": ["utilization": 0.12],
            "seven_day": ["utilization": 0.45],
            "limits": [["kind": "weekly_scoped", "group": "weekly", "percent": 33,
                        "scope": ["model": ["id": "fable", "display_name": "Fable"]]]]
        ])
        let mixedMeters = try #require(ClaudeOAuthParser.usage(mixed)?.accountDetails.quotaMeters)
        #expect(mixedMeters.map(\.window.usedPercent) == [12, 45, 33])
    }

    @Test("Credentials expose only selected fields and redact descriptions")
    func credentialRedaction() throws {
        let data = Data(#"{"claudeAiOauth":{"accessToken":"fixture-secret","refreshToken":"fixture-refresh","expiresAt":1900000000000,"subscriptionType":"max","scopes":["usage"]}}"#.utf8)
        let parsed = try #require(ClaudeOAuthParser.credential(data))
        #expect(parsed.token == "fixture-secret")
        #expect(parsed.subscriptionType == "max")
        #expect(!String(describing: parsed).contains("fixture-secret"))
        #expect(!String(reflecting: parsed).contains("fixture-refresh"))
    }

    @Test("401 rereads once, then pauses for an unchanged token")
    func unauthorizedPauses() async {
        let mock = OAuthMock(status: 401)
        let provider = ClaudeOAuthUsageProvider(reader: { await mock.read() }, transport: { _ in await mock.respond() })
        let first = await provider.fetch(authorized: true)
        #expect(first.snapshot.state == .unavailable)
        #expect(await mock.reads == 2)
        #expect(await mock.requests == 1)
        _ = await provider.fetch(authorized: true)
        #expect(await mock.reads == 2)
        #expect(await mock.requests == 1)
    }

    @Test("429 respects Retry-After with at least a one-minute pause")
    func rateLimitPauses() async {
        let mock = OAuthMock(status: 429)
        let provider = ClaudeOAuthUsageProvider(reader: { await mock.read() }, transport: { _ in await mock.respond() })
        _ = await provider.fetch(authorized: true)
        await provider.resumeAfterUserAction()
        _ = await provider.fetch(authorized: true)
        #expect(await mock.requests == 1)
        #expect(ClaudeOAuthUsageProvider.retryDate("3", now: now) == now.addingTimeInterval(60))
    }

    @Test("Automatic selection rejects windows after reset and favors current data")
    func selection() throws {
        let stale = try #require(ClaudeOAuthParser.usage(Data(#"{"five_hour":{"utilization":20,"resets_at":"2030-01-01T00:00:00Z"}}"#.utf8), capturedAt: now.addingTimeInterval(-600)))
        let current = try #require(ClaudeOAuthParser.usage(Data(#"{"five_hour":{"utilization":30,"resets_at":"2030-01-01T00:00:00Z"}}"#.utf8), capturedAt: now))
        #expect(ClaudeUsageResolver.select([stale, current], now: now)?.snapshot.quota?.usedPercent == 30)
        #expect(ClaudeUsageResolver.valid(stale, now: Date(timeIntervalSince1970: 1_800_000_000 + 100_000_000)) == nil)
    }

    @Test("Reads the local Claude plan file and rejects empty or damaged files")
    func planFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("claude-plan-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"version":2,"samples":[{"t":1800000000000,"org":"ignored","u":{"fh":2,"sd":3}}]}"#.utf8).write(to: url)
        let parsed = try #require(ClaudePlanUsageReader.read(fileURL: url))
        #expect(parsed.accountDetails.quotaMeters.count == 2)
        #expect(parsed.accountDetails.quotaMeters.first?.window.resetsAt == nil)
        try Data(#"{"samples":[]}"#.utf8).write(to: url)
        #expect(ClaudePlanUsageReader.read(fileURL: url) == nil)
        try Data("broken".utf8).write(to: url)
        #expect(ClaudePlanUsageReader.read(fileURL: url) == nil)
    }
}

private actor OAuthMock {
    var reads = 0
    var requests = 0
    let status: Int
    init(status: Int) { self.status = status }
    func read() -> Data? {
        reads += 1
        return Data(#"{"claudeAiOauth":{"accessToken":"fixture-secret","expiresAt":1900000000000}}"#.utf8)
    }
    func respond() -> (Int, Data, String?) {
        requests += 1
        return (status, Data(), "3")
    }
}
