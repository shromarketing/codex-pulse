import Foundation

struct PaceEngine: Sendable {
    func insight(for snapshot: ProviderSnapshot, history: [UsagePoint], now: Date = .now) -> PaceInsight {
        guard let quota = snapshot.quota else { return .unknown }
        let remaining = quota.remainingPercent
        let resetAt = quota.resetsAt
        let providerPoints = history
            .filter { $0.provider == snapshot.provider }
            .sorted { $0.date < $1.date }
        let recent = Array(providerPoints.suffix(48))

        let burnPerDay: Double?
        if let first = recent.first, let last = recent.last, last.date > first.date {
            let usedDelta = last.usedPercent - first.usedPercent
            let days = last.date.timeIntervalSince(first.date) / 86_400
            burnPerDay = usedDelta > 0 && days > 0.02 ? usedDelta / days : nil
        } else {
            burnPerDay = nil
        }

        let projectedExhaustion: Date?
        if let burnPerDay, burnPerDay > 0 {
            projectedExhaustion = now.addingTimeInterval((remaining / burnPerDay) * 86_400)
        } else {
            projectedExhaustion = nil
        }

        let safeToday: Double?
        if let resetAt, resetAt > now {
            let daysLeft = max(resetAt.timeIntervalSince(now) / 86_400, 1.0 / 24.0)
            safeToday = min(remaining, remaining / daysLeft)
        } else {
            safeToday = nil
        }

        let level: HealthLevel
        if remaining <= 10 {
            level = .critical
        } else if let projectedExhaustion, let resetAt, projectedExhaustion < resetAt {
            level = remaining <= 20 ? .critical : .watch
        } else if remaining <= 25 {
            level = .watch
        } else {
            level = .healthy
        }

        return PaceInsight(
            level: level,
            burnPercentPerDay: burnPerDay,
            safePercentToday: safeToday,
            projectedExhaustion: projectedExhaustion,
            resetAt: resetAt
        )
    }
}
