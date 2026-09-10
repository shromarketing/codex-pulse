import Foundation

actor UsageHistoryStore {
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("CodexPulse", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("usage-history.json")
    }

    func load() -> [UsagePoint] {
        guard let data = try? Data(contentsOf: fileURL),
              let points = try? JSONDecoder().decode([UsagePoint].self, from: data)
        else { return [] }
        return points
    }

    func record(_ snapshots: [ProviderSnapshot]) -> [UsagePoint] {
        var points = load()
        for snapshot in snapshots where snapshot.state == .connected {
            guard let used = snapshot.quota?.usedPercent else { continue }
            let previous = points.last { $0.provider == snapshot.provider }
            let shouldRecord: Bool
            if let previous {
                let moved = abs(previous.usedPercent - used) >= 0.25
                let stale = Date().timeIntervalSince(previous.date) >= 30 * 60
                shouldRecord = moved || stale
            } else {
                shouldRecord = true
            }
            if shouldRecord {
                points.append(UsagePoint(date: .now, provider: snapshot.provider, usedPercent: used))
            }
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .distantPast
        points = points.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
        if let data = try? JSONEncoder().encode(points) {
            try? data.write(to: fileURL, options: .atomic)
        }
        return points
    }
}
