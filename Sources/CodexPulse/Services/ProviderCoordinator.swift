import Foundation

struct ProviderCoordinator: Sendable {
    func fetchCodex() async -> ProviderSnapshot {
        let direct = await CodexAppServerProvider().fetch()
        if direct.state == .connected { return direct }
        let fallback = await CodexBarBridgeProvider(provider: .codex).fetch()
        return fallback.state == .connected ? fallback : direct
    }

    func fetchClaude() async -> ProviderSnapshot {
        await CodexBarBridgeProvider(provider: .claude).fetch()
    }
}
