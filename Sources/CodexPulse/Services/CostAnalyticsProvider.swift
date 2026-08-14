import Foundation

actor CostAnalyticsProvider {
    func fetch(days: Int = 30) async -> [ProviderKind: UsageAnalyticsSnapshot] {
        guard let executable = ExecutableLocator.locate("codexbar") else { return [:] }

        do {
            let result = try await CommandRunner.run(
                executable: executable,
                arguments: [
                    "cost",
                    "--provider", "both",
                    "--days", String(days),
                    "--format", "json",
                    "--provider-native-only",
                ],
                timeout: 35
            )
            guard let data = result.stdout.data(using: .utf8) else { return [:] }
            let payloads = try JSONDecoder().decode([CostPayload].self, from: data)
            return Dictionary(uniqueKeysWithValues: payloads.compactMap { payload in
                guard let provider = ProviderKind(rawValue: payload.provider) else { return nil }
                return (provider, payload.snapshot(provider: provider))
            })
        } catch {
            return [:]
        }
    }
}

private struct CostPayload: Decodable {
    let provider: String
    let currencyCode: String?
    let source: String?
    let updatedAt: String?
    let totals: CostTotalsPayload?
    let daily: [DailyPayload]?
    let projects: [ProjectPayload]?

    func snapshot(provider: ProviderKind) -> UsageAnalyticsSnapshot {
        let formatter = ISO8601DateFormatter()
        return UsageAnalyticsSnapshot(
            provider: provider,
            currencyCode: currencyCode ?? "USD",
            source: source ?? "Local compatibility bridge",
            updatedAt: updatedAt.flatMap(formatter.date(from:)) ?? .now,
            totals: totals?.model ?? .zero,
            daily: (daily ?? []).map(\.model),
            projects: (projects ?? []).map(\.model),
            accountSummary: nil,
            accountDaily: []
        )
    }
}

private struct CostTotalsPayload: Decodable {
    let inputTokens: Int64?
    let cacheReadTokens: Int64?
    let outputTokens: Int64?
    let totalTokens: Int64?
    let totalCost: Double?

    var model: TokenTotals {
        TokenTotals(
            inputTokens: inputTokens ?? 0,
            cacheReadTokens: cacheReadTokens ?? 0,
            outputTokens: outputTokens ?? 0,
            totalTokens: totalTokens ?? 0,
            totalCost: totalCost
        )
    }
}

private struct ModelPayload: Decodable {
    let modelName: String
    let totalTokens: Int64?
    let cost: Double?

    var model: ModelUsage {
        ModelUsage(modelName: modelName, totalTokens: totalTokens ?? 0, cost: cost)
    }
}

private struct DailyPayload: Decodable {
    let date: String
    let inputTokens: Int64?
    let cacheReadTokens: Int64?
    let outputTokens: Int64?
    let totalTokens: Int64?
    let totalCost: Double?
    let modelBreakdowns: [ModelPayload]?

    var model: DailyTokenUsage {
        DailyTokenUsage(
            date: date,
            inputTokens: inputTokens ?? 0,
            cacheReadTokens: cacheReadTokens ?? 0,
            outputTokens: outputTokens ?? 0,
            totalTokens: totalTokens ?? 0,
            totalCost: totalCost,
            modelBreakdowns: (modelBreakdowns ?? []).map(\.model)
        )
    }
}

private struct ProjectPayload: Decodable {
    let name: String
    let path: String?
    let totalTokens: Int64?
    let totalCost: Double?
    let modelBreakdowns: [ModelPayload]?
    let daily: [DailyPayload]?

    var model: ProjectUsage {
        ProjectUsage(
            name: name,
            path: path ?? "",
            totalTokens: totalTokens ?? 0,
            totalCost: totalCost,
            modelBreakdowns: (modelBreakdowns ?? []).map(\.model),
            daily: (daily ?? []).map(\.model)
        )
    }
}
