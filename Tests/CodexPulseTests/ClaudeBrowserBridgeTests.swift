import Foundation
import Testing
@testable import CodexPulse

@Suite("Claude Pulse Connector")
struct ClaudeBrowserBridgeTests {
    @Test("Parses sanitized extension data without browser credentials")
    func parsesSanitizedUsage() throws {
        let payload = #"""
        {
          "schemaVersion": 1,
          "capturedAt": "2026-08-12T00:00:00Z",
          "windows": [
            {"id":"claude-session","scope":"session","title":null,"utilization":12,"resetsAt":"2026-08-12T04:36:00Z"},
            {"id":"claude-weekly","scope":"weekly","title":null,"utilization":66,"resetsAt":"2026-08-12T03:16:00Z"},
            {"id":"claude-seven-day-fable","scope":"modelWeekly","title":"Fable","utilization":74,"resetsAt":"2026-08-12T03:16:00Z"}
          ],
          "plan": {"rateLimitTier":"max_5x","billingType":null,"seatTier":null}
        }
        """#.data(using: .utf8)!

        let result = try ClaudeBrowserBridgeParser.parse(payload)
        #expect(result.snapshot.state == .connected)
        #expect(result.snapshot.remainingPercent == 26)
        #expect(result.accountDetails.quotaMeters.count == 3)
        #expect(result.accountDetails.planName == "Claude Max 5x")
        #expect(result.accountDetails.quotaMeters.first { $0.scope == .session }?.window.remainingPercent == 88)
    }

    @Test("Rejects payloads with no readable quota windows")
    func rejectsEmptyPayload() {
        let payload = #"{"schemaVersion":1,"capturedAt":null,"windows":[],"plan":null}"#.data(using: .utf8)!
        #expect(throws: ClaudeBrowserBridgeParser.ParseError.self) {
            _ = try ClaudeBrowserBridgeParser.parse(payload)
        }
    }

    @Test("Prefers a known reset when Claude windows have equal usage")
    func prefersKnownResetOnEqualUsage() throws {
        let payload = #"""
        {
          "schemaVersion": 1,
          "capturedAt": "2026-08-12T00:00:00Z",
          "windows": [
            {"id":"claude-session","scope":"session","title":null,"utilization":0,"resetsAt":null},
            {"id":"claude-weekly","scope":"weekly","title":null,"utilization":0,"resetsAt":"2026-08-18T00:00:00Z"}
          ],
          "plan": null
        }
        """#.data(using: .utf8)!

        let result = try ClaudeBrowserBridgeParser.parse(payload)
        #expect(result.snapshot.quota?.resetsAt != nil)
        #expect(result.snapshot.quota?.windowMinutes == 10_080)
    }

    @Test("Accepts a complete localhost request")
    func acceptsCompleteRequest() throws {
        let body = #"{"schemaVersion":1}"#.data(using: .utf8)!
        let head = "POST /v1/claude/usage?source=extension HTTP/1.1\r\n" +
            "Host: 127.0.0.1:37421\r\n" +
            "Authorization: Bearer local-token\r\n" +
            "Content-Length: \(body.count)\r\n\r\n"
        var requestData = Data(head.utf8)
        requestData.append(body)

        let request = try #require(BridgeHTTPRequest(data: requestData))
        #expect(request.method == "POST")
        #expect(request.path == "/v1/claude/usage")
        #expect(request.headers["authorization"] == "Bearer local-token")
        #expect(request.body == body)
    }

    @Test("Rejects oversized connector bodies")
    func rejectsOversizedBody() {
        let head = "POST /v1/claude/usage HTTP/1.1\r\n" +
            "Content-Length: \(BridgeHTTPRequest.maximumBodyBytes + 1)\r\n\r\n"
        #expect(BridgeHTTPRequest(data: Data(head.utf8)) == nil)
    }

    @Test("Rejects oversized connector headers")
    func rejectsOversizedHeaders() {
        let padding = String(repeating: "a", count: BridgeHTTPRequest.maximumHeaderBytes)
        let head = "GET /v1/health HTTP/1.1\r\nX-Padding: \(padding)\r\n\r\n"
        #expect(BridgeHTTPRequest(data: Data(head.utf8)) == nil)
    }
}
