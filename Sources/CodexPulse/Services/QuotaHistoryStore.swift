import Foundation

actor QuotaHistoryStore {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            return
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("CodexPulse", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("quota-window-history.json")
    }

    func load() -> [QuotaHistoryPoint] {
        guard let data = try? Data(contentsOf: fileURL),
              let points = try? JSONDecoder().decode([QuotaHistoryPoint].self, from: data)
        else { return [] }
        return sanitized(points)
    }

    func record(
        _ samples: [QuotaHistorySample],
        now: Date = .now
    ) -> [QuotaHistoryPoint] {
        var points = load()
        for sample in samples where sample.usedPercent.isFinite {
            let used = min(100, max(0, sample.usedPercent))
            let previous = points.last {
                $0.provider == sample.provider && $0.windowID == sample.windowID
            }
            let shouldRecord: Bool
            if let previous {
                let moved = abs(previous.usedPercent - used) >= 0.25
                let stale = now.timeIntervalSince(previous.date) >= 30 * 60
                let resetChanged = resetBoundaryChanged(previous.resetsAt, sample.resetsAt)
                shouldRecord = moved || stale || resetChanged
            } else {
                shouldRecord = true
            }
            guard shouldRecord else { continue }
            points.append(QuotaHistoryPoint(
                date: now,
                provider: sample.provider,
                windowID: sample.windowID,
                scope: sample.scope,
                title: sample.title,
                usedPercent: used,
                resetsAt: sample.resetsAt,
                windowMinutes: sample.windowMinutes
            ))
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: now) ?? .distantPast
        points = points.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
        if let data = try? JSONEncoder().encode(points) {
            try? data.write(to: fileURL, options: .atomic)
        }
        return points
    }

    /// Providers can return a rounded "resets in" duration rather than one stable timestamp.
    /// Recomputing that duration on every refresh moves `resetsAt` by a few seconds, which is
    /// transport noise rather than a new quota period.
    private func resetBoundaryChanged(_ previous: Date?, _ current: Date?) -> Bool {
        switch (previous, current) {
        case (nil, nil):
            false
        case let (previous?, current?):
            abs(previous.timeIntervalSince(current)) > 90 * 60
        default:
            true
        }
    }

    /// Removes noisy points written by earlier builds while preserving real percentage changes
    /// and the regular 30-minute heartbeat used to draw a continuous history.
    private func sanitized(_ source: [QuotaHistoryPoint]) -> [QuotaHistoryPoint] {
        var latestByWindow: [String: QuotaHistoryPoint] = [:]
        var result: [QuotaHistoryPoint] = []
        for point in source.sorted(by: { $0.date < $1.date }) {
            let key = "\(point.provider.rawValue)-\(point.windowID)"
            if let previous = latestByWindow[key] {
                let moved = abs(previous.usedPercent - point.usedPercent) >= 0.25
                let stale = point.date.timeIntervalSince(previous.date) >= 30 * 60
                let resetChanged = resetBoundaryChanged(previous.resetsAt, point.resetsAt)
                guard moved || stale || resetChanged else { continue }
            }
            result.append(point)
            latestByWindow[key] = point
        }
        return result
    }
}
