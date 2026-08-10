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
        let calendar = Calendar.current
        for snapshot in snapshots where snapshot.state == .connected {
            guard let used = snapshot.quota?.usedPercent else { continue }
            points.removeAll {
                $0.provider == snapshot.provider && calendar.isDate($0.date, inSameDayAs: .now)
            }
            points.append(UsagePoint(date: .now, provider: snapshot.provider, usedPercent: used))
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .distantPast
        points = points.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
        if let data = try? JSONEncoder().encode(points) {
            try? data.write(to: fileURL, options: .atomic)
        }
        return points
    }
}
