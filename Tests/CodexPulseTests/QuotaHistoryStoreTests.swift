import Foundation
import Testing
@testable import CodexPulse

@Suite("Quota window history")
struct QuotaHistoryStoreTests {
    @Test("Stores Claude session, weekly, and model windows independently")
    func storesIndependentClaudeWindows() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-pulse-quota-history-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = QuotaHistoryStore(fileURL: fileURL)
        let now = Date(timeIntervalSince1970: 1_786_487_200)
        let samples = claudeSamples(reset: now.addingTimeInterval(3_600))

        let initial = await store.record(samples, now: now)
        #expect(initial.count == 3)
        #expect(Set(initial.map(\.windowID)) == ["claude-session", "claude-weekly", "claude-fable"])

        let unchanged = await store.record(samples, now: now.addingTimeInterval(120))
        #expect(unchanged.count == 3)

        var changed = samples
        changed[1] = QuotaHistorySample(
            provider: .claude,
            windowID: "claude-weekly",
            scope: .weekly,
            title: nil,
            usedPercent: 22,
            resetsAt: now.addingTimeInterval(3_600),
            windowMinutes: 10_080
        )
        let withMovement = await store.record(changed, now: now.addingTimeInterval(180))
        #expect(withMovement.count == 4)
        #expect(withMovement.last?.windowID == "claude-weekly")
        #expect(withMovement.last?.usedPercent == 22)
    }

    @Test("Records a changed reset even when utilization is unchanged")
    func recordsResetBoundary() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-pulse-quota-reset-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = QuotaHistoryStore(fileURL: fileURL)
        let now = Date(timeIntervalSince1970: 1_786_487_200)
        _ = await store.record(claudeSamples(reset: now.addingTimeInterval(3_600)), now: now)
        let afterReset = await store.record(
            claudeSamples(reset: now.addingTimeInterval(6 * 3_600)),
            now: now.addingTimeInterval(60)
        )
        #expect(afterReset.count == 6)
    }

    @Test("Ignores small countdown drift and cleans legacy noise")
    func ignoresResetCountdownDrift() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-pulse-quota-drift-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = QuotaHistoryStore(fileURL: fileURL)
        let now = Date(timeIntervalSince1970: 1_786_487_200)
        _ = await store.record(claudeSamples(reset: now.addingTimeInterval(3_600)), now: now)

        let drifted = await store.record(
            claudeSamples(reset: now.addingTimeInterval(3_600 + 20 * 60)),
            now: now.addingTimeInterval(120)
        )

        #expect(drifted.count == 3)
    }

    private func claudeSamples(reset: Date) -> [QuotaHistorySample] {
        [
            QuotaHistorySample(
                provider: .claude,
                windowID: "claude-session",
                scope: .session,
                title: nil,
                usedPercent: 12,
                resetsAt: reset,
                windowMinutes: 300
            ),
            QuotaHistorySample(
                provider: .claude,
                windowID: "claude-weekly",
                scope: .weekly,
                title: nil,
                usedPercent: 18,
                resetsAt: reset,
                windowMinutes: 10_080
            ),
            QuotaHistorySample(
                provider: .claude,
                windowID: "claude-fable",
                scope: .modelWeekly,
                title: "Fable",
                usedPercent: 27,
                resetsAt: reset,
                windowMinutes: 10_080
            ),
        ]
    }
}
