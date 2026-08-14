import Foundation

struct ProviderCoordinator: Sendable {
    func fetchCodex() async -> ProviderSnapshot {
        await fetchCodexData().snapshot
    }

    func fetchCodexData() async -> CodexProviderData {
        let direct = await CodexAppServerProvider().fetchData()
        if direct.snapshot.state == .connected { return direct }
        let fallback = await CodexBarBridgeProvider(provider: .codex).fetch()
        return CodexProviderData(
            snapshot: fallback.state == .connected ? fallback : direct.snapshot,
            accountSummary: direct.accountSummary,
            accountDaily: direct.accountDaily,
            accountDetails: direct.accountDetails
        )
    }

    func fetchClaudeData(
        source: ClaudeUsageSource,
        allowBrowserCookieImport: Bool = false
    ) async -> ClaudeProviderData {
        if source == .browserExtension {
            return ClaudeBrowserBridge.shared.latestData
                ?? .unavailable(message: "Pulse Connector is waiting for Claude Web data")
        }
        return await CodexBarBridgeProvider(provider: .claude).fetchClaudeData(
            source: source,
            allowBrowserCookieImport: allowBrowserCookieImport
        )
    }
}
