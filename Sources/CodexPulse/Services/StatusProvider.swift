import Foundation

struct StatusProvider: Sendable {
    func fetch(providers: Set<ProviderKind>) async -> [ProviderKind: ServiceHealthSnapshot] {
        var values: [ServiceHealthSnapshot] = []
        await withTaskGroup(of: ServiceHealthSnapshot.self) { group in
            for provider in providers {
                group.addTask {
                    let url = provider == .codex
                        ? URL(string: "https://status.openai.com/api/v2/status.json")!
                        : URL(string: "https://status.anthropic.com/api/v2/status.json")!
                    return await fetch(provider: provider, url: url)
                }
            }
            for await value in group { values.append(value) }
        }
        return Dictionary(uniqueKeysWithValues: values.map { ($0.provider, $0) })
    }

    private func fetch(provider: ProviderKind, url: URL) async -> ServiceHealthSnapshot {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = payload["status"] as? [String: Any]
            else { throw URLError(.badServerResponse) }
            let indicator = (status["indicator"] as? String ?? "none").lowercased()
            let description = status["description"] as? String ?? ""
            let state: ServiceHealthState
            switch indicator {
            case "none": state = .operational
            case "minor": state = .degraded
            case "major", "critical": state = .outage
            default: state = .unknown
            }
            return ServiceHealthSnapshot(provider: provider, state: state, message: description, updatedAt: .now)
        } catch {
            return ServiceHealthSnapshot(provider: provider, state: .unknown, message: "Status unavailable", updatedAt: .now)
        }
    }
}
