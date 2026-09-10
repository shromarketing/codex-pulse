import Foundation
import Testing
@testable import CodexPulse

@Suite("Reset announcement monitor")
struct ResetSignalMonitorTests {
    @Test("Claude Statuspage accepts only explicit quota reset or expansion messages")
    @MainActor
    func decodesExplicitClaudeAnnouncements() throws {
        let signals = try ClaudeResetSignalMonitor.decodeSignals(from: claudeFixtureData)

        #expect(signals.count == 2)
        #expect(signals.map(\.provider).allSatisfy { $0 == .claude })
        #expect(signals.map(\.source).allSatisfy { $0 == .claudeStatus })
        #expect(signals.map(\.kind).contains(.usageReset))
        #expect(signals.map(\.kind).contains(.quotaExpansion))
        #expect(signals.allSatisfy { $0.sourceURL.host == "stspg.io" })
    }

    @Test("Claude Statuspage signal baseline is quiet and a new update alerts once")
    @MainActor
    func deduplicatesClaudeStatusUpdates() throws {
        let suite = "codex-pulse-claude-reset-signals-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let monitor = ClaudeResetSignalMonitor(defaults: defaults)
        let initial = try ClaudeResetSignalMonitor.decodeSignals(from: claudeFixtureData)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(monitor.ingest(initial, checkedAt: now).signalToNotify == nil)
        #expect(monitor.ingest(initial, checkedAt: now.addingTimeInterval(60)).signalToNotify == nil)

        let newSignal = ResetSignal(
            id: "claude-status-new",
            kind: .usageReset,
            sourceURL: try #require(URL(string: "https://stspg.io/claude-reset")),
            publishedAt: now.addingTimeInterval(120),
            timingHint: nil,
            estimatedResetAt: nil,
            provider: .claude,
            source: .claudeStatus
        )
        let update = monitor.ingest([newSignal] + initial, checkedAt: now.addingTimeInterval(120))
        #expect(update.signalToNotify?.id == "claude-status-new")
        #expect(update.status.state == .signal)
    }

    @Test("Accepts only explicit reset announcements from Tibo")
    @MainActor
    func decodesExplicitAnnouncements() throws {
        let signals = try ResetSignalMonitor.decodeSignals(from: fixtureData)

        #expect(signals.count == 3)
        #expect(signals.map(\.kind).contains(.bankedReset))
        #expect(signals.map(\.kind).contains(.usageReset))
        #expect(signals.first(where: { $0.kind == .bankedReset })?.timingHint == "end of day")
        #expect(signals.first(where: { $0.kind == .bankedReset })?.summary?.contains("full banked reset") == true)
        #expect(signals.first(where: { $0.kind == .bankedReset })?.estimatedResetAt == nil)
        #expect(signals.first(where: { $0.kind == .usageReset })?.estimatedResetAt == Date(timeIntervalSince1970: 1_788_658_765))
        #expect(signals.first(where: { $0.id == "clock" })?.estimatedResetAt == Date(timeIntervalSince1970: 1_788_674_400))
        let banked = try #require(signals.first(where: { $0.kind == .bankedReset }))
        #expect(
            resetSignalSummary(banked, language: .russian)
                == "Tibo сообщает: для пользователей Plus и Pro планируют выдать сохранённый сброс лимита (banked reset), который можно применить позже вручную."
        )
        #expect(signals.allSatisfy { $0.sourceURL.host == "x.com" })
    }

    @Test("First successful poll is a quiet baseline and later items notify once")
    @MainActor
    func deduplicatesAfterBaseline() throws {
        let suite = "codex-pulse-reset-signals-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let monitor = ResetSignalMonitor(defaults: defaults)
        let initial = try ResetSignalMonitor.decodeSignals(from: fixtureData)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let baseline = monitor.ingest(initial, checkedAt: now)
        #expect(baseline.signalToNotify == nil)
        #expect(baseline.status.state == .checked)
        #expect(baseline.status.recentSignals.count == 3)

        let repeated = monitor.ingest(initial, checkedAt: now.addingTimeInterval(60))
        #expect(repeated.signalToNotify == nil)

        let newSignal = ResetSignal(
            id: "new-reset",
            kind: .usageReset,
            sourceURL: try #require(URL(string: "https://x.com/thsottiaux/status/new-reset")),
            publishedAt: now.addingTimeInterval(120),
            timingHint: "next hour",
            estimatedResetAt: now.addingTimeInterval(120 + 60 * 60)
        )
        let update = monitor.ingest([newSignal] + initial, checkedAt: now.addingTimeInterval(120))
        #expect(update.signalToNotify?.id == "new-reset")
        #expect(update.status.state == .signal)
    }

    private var fixtureData: Data {
        Data(#"""
        {
          "source": {"user_name": "thsottiaux"},
          "items": [
            {"id":"banked","external_id":"banked","author":"thsottiaux","content":"We will do the full banked reset today too for Plus and Pro. Lands end of day.","url":"https://x.com/thsottiaux/status/banked","published_at":"2026-09-05T00:39:25"},
            {"id":"usage","external_id":"usage","author":"thsottiaux","content":"We are resetting Codex usage limits in the next hour.","url":"https://x.com/thsottiaux/status/usage","published_at":"2026-09-06T00:39:25"},
            {"id":"clock","external_id":"clock","author":"thsottiaux","content":"We are resetting Codex limits at 2:00 AM ET tomorrow.","url":"https://x.com/thsottiaux/status/clock","published_at":"2026-09-06T00:39:25"},
            {"id":"other","external_id":"other","author":"thsottiaux","content":"Codex is faster today.","url":"https://x.com/thsottiaux/status/other","published_at":"2026-09-06T01:39:25"},
            {"id":"spoof","external_id":"spoof","author":"someone-else","content":"We will reset Codex limits today.","url":"https://x.com/someone-else/status/spoof","published_at":"2026-09-06T02:39:25"}
          ]
        }
        """#.utf8)
    }

    private var claudeFixtureData: Data {
        Data(#"""
        {
          "incidents": [
            {
              "id": "ordinary",
              "name": "Elevated errors for Claude Code",
              "shortlink": "https://stspg.io/ordinary",
              "created_at": "2026-09-08T08:00:00.000Z",
              "updated_at": "2026-09-08T08:01:00.000Z",
              "incident_updates": [
                {"id":"ordinary-update","body":"We are investigating elevated errors for Claude Code.","created_at":"2026-09-08T08:01:00.000Z"}
              ]
            },
            {
              "id": "reset",
              "name": "Claude account update",
              "shortlink": "https://stspg.io/reset",
              "created_at": "2026-09-08T09:00:00.000Z",
              "updated_at": "2026-09-08T09:01:00.000Z",
              "incident_updates": [
                {"id":"reset-update","body":"We have reset affected usage limits for Claude Code users.","created_at":"2026-09-08T09:01:00.000Z"}
              ]
            },
            {
              "id": "boost",
              "name": "Claude account update",
              "shortlink": "https://stspg.io/boost",
              "created_at": "2026-09-08T10:00:00.000Z",
              "updated_at": "2026-09-08T10:01:00.000Z",
              "incident_updates": [
                {"id":"boost-update","body":"A temporary increase to Claude usage limits is now available.","created_at":"2026-09-08T10:01:00.000Z"}
              ]
            }
          ]
        }
        """#.utf8)
    }
}
