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
        allowBrowserCookieImport: Bool = false,
        oauthAuthorized: Bool = false
    ) async -> ClaudeProviderData {
        let connector = ClaudeBrowserBridge.shared.latestData
        switch source {
        case .off:
            return .unavailable(message: "Claude is not connected")
        case .browserExtension:
            return ClaudeUsageResolver.valid(connector)
                ?? .unavailable(message: "Pulse Connector is waiting for current Claude Web data")
        case .oauth:
            let direct = await ClaudeOAuthUsageProvider.shared.fetch(authorized: oauthAuthorized)
            return ClaudeUsageResolver.valid(direct) ?? direct
        case .automatic:
            let oauth = await ClaudeOAuthUsageProvider.shared.fetch(authorized: oauthAuthorized)
            let file = ClaudeUsageResolver.inheritingResetTimes(ClaudePlanUsageReader.read(), from: [oauth, connector])
            if let chosen = ClaudeUsageResolver.select([oauth, connector, file]) {
                return chosen
            }
            return .unavailable(message: oauth.snapshot.message ?? "No current Claude quota data is available")
        case .web, .legacyOAuth:
            let bridge = await CodexBarBridgeProvider(provider: .claude).fetchClaudeData(
                source: source, allowBrowserCookieImport: allowBrowserCookieImport)
            return ClaudeUsageResolver.valid(bridge) ?? bridge
        }
    }
}
