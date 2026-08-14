# Architecture

## Runtime

- Native SwiftUI + AppKit, macOS 13+.
- `MenuBarExtra` for the status item.
- `NSPanel` for the always-on-top widget.
- `Swift Charts` for local quota history.
- Local aggregate cost analytics through a clearly labeled CodexBar-compatible bridge when installed.
- Public OpenAI and Anthropic status endpoints for optional service-health checks, kept separate from local account connection state.
- Independent caches: lightweight quota refreshes stay responsive while expensive local cost scans and public status checks run less often.
- Cost analytics are collected as one 90-day base snapshot. The 7/30/90-day totals, models, projects, account-day rows, and receipts are derived synchronously in memory, so changing a period never spawns a CLI process or blocks the interface.
- Quota analytics use a separate versioned local history. Every Codex and Claude window is keyed independently by provider and window ID; a point is recorded when utilization moves by at least 0.25 percentage points, the reset boundary changes, or the previous point is 30 minutes old. Data is retained for 90 days.
- The Usage screen keeps unlike units separate: quota history is charted as utilization percent for both providers, while token, cache, output, project, model, and cost views include only providers whose local source returned those aggregates.
- Scheduled quota/status synchronization is intentionally quiet. Only first load and explicit user refreshes show the toolbar activity indicator, so background polling cannot make local navigation look blocked.
- The menu popover owns a bounded screen-aware height so its central `ScrollView` always receives layout space instead of collapsing to zero.
- The floating `NSPanel` uses geometry-driven Mini, Compact, Focus, and Expanded layouts; a completed live resize persists as Adaptive, while implausibly small restored Adaptive frames fall back to the useful default size.
- Daily activity pre-groups local aggregates by calendar day before rendering. The same path supports 7/30/90-day views without repeating project scans for every cell.
- Quota presentation uses shared pure helpers for reset and exhaustion copy. `PaceEngine` accepts an injected clock, so the UI and tests can distinguish a provider reset from the earlier exhaustion forecast without timing-dependent assertions.
- Mini, Compact, Focus, and Expanded widget layouts share one refresh action. The native button reports its busy state through accessibility and never launches a task.
- Compact treats the reset and exhaustion forecast as independent facts: a persistent weekly-reset line uses provider time, while the pace line uses local history.
- Compact has a content-driven minimum height of 100 pt and a 260 × 138 pt preset. Restored legacy default widths of 320/360 pt migrate to the new Compact preset, while genuine custom Adaptive frames such as 490 × 108 pt remain untouched; only a live frame below 100 pt renders Mini.
- Focus and Expanded keep the provider header and controls outside a vertical `ScrollView`. Their quota, pace, metrics, usage chart, model, and project content remains present and scrollable instead of being gated or clipped by window height.
- Focus and Expanded reuse one `paceSummary` surface whose frame expands before its semantic background is applied, keeping the status card aligned with every other full-width section.
- Startup restores local history and shows the configured floating panel before awaiting provider and analytics refreshes. The panel owns the same observable state and fills in live data as each startup refresh completes.
- The `NSPanel` keeps its resizable/closable capabilities but permanently hides AppKit's close, miniaturize, and zoom buttons. SwiftUI owns the single visible control group—refresh, expand/collapse, and close—inside the widget at the top right.

## Provider contract

Each provider returns a `ProviderSnapshot` containing connection state, a limiting quota window, source label, update time, and optional local history. Codex and Claude also return sanitized account details with all reported quota buckets, plan type, and optional credit metadata. The UI does not know how credentials work.

### Codex

Primary: spawn the local `codex app-server`, complete the documented initialization handshake, and read `account/rateLimits/read`. The client extracts only percentage/reset metadata, every reported rate-limit bucket, the plan type, and optional credit balance metadata.

The same handshake reads `account/usage/read` for account-level token summaries and daily buckets. It does not request stored thread bodies.

Fallback: invoke an installed CodexBar CLI in read-only JSON mode.

### Claude

Primary: the bundled Manifest V3 Pulse Connector runs read-only Usage requests in the main world of an already signed-in `claude.ai` tab. Chrome keeps the browser session; the extension sanitizes the response to percentage, reset, scope, model title, capture time, and plan-label fields before posting it to `127.0.0.1:37421`.

The local bridge binds only to loopback. Pairing uses an eight-character code that expires after ten minutes, rate-limits failed attempts, returns a random 256-bit token once, and persists only its SHA-256 hash in Pulse. Disconnecting revokes the hash. The raw token remains in the paired Chrome profile's extension storage; no Claude cookie or session credential is sent to the app.

Fallback: after separate explicit consent, Pulse can invoke an installed CodexBar CLI in read-only Web/OAuth/Auto mode. That process owns any cookie/Keychain access; Pulse still receives only aggregate JSON. The shared parser retains session, all-model weekly, model-specific weekly, reset, plan, and optional credit-balance fields while discarding account identity and raw credentials.

The limiting known window becomes the provider summary used by the menu-bar meter and pace engine. Reset-only synthetic placeholders remain visible as diagnostics but never masquerade as an exhausted quota.

Before public stable release, package/sign the extension distribution path and keep the optional compatibility fallback clearly attributed.

## Privacy

- Provider outputs are sanitized before messages reach the UI.
- Account identities are discarded.
- Task router is hybrid. A deterministic local profile produces an immediate route and enforces minimum model/effort floors for scale, high-stakes work, and verification. After an explicit user action, an ephemeral `codex exec` request can refine the route as strict structured JSON. Pulse sends only the typed task, runs the classifier with Luna/low in a temporary read-only workspace, removes temporary schema files, and never stores the task or creates an API key. CLI failure or timeout keeps the safe local fallback visible.
- Only timestamped quota percentages, reset metadata, non-identifying window labels, and app preferences are written by Pulse to Application Support.
- The legacy provider-level quota history remains available to pace forecasting; the window-level history powers 7/30/90-day charts and reset events without reading chats.
- Usage intelligence and history consume aggregate model/project/day data and discard account identities and prompt text.

## Release updates

Manual Refresh calls the existing provider/analytics refresh path and does not replace the app. The initial public preview uses GitHub Releases with a universal ZIP, drag-to-Applications DMG, connector ZIP, checksums and a local source-build route. These artifacts are ad-hoc signed and clearly labeled as not Developer ID signed or notarized. Sparkle stays disabled until a Developer ID signed and notarized archive plus an Ed25519-signed appcast are available; application updates will then use a separate “Check for Updates” action.
