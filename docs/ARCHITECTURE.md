# Architecture

## Runtime

- Native SwiftUI + AppKit, macOS 13+.
- `MenuBarExtra` for the status item.
- `NSPanel` for the always-on-top widget.
- `Swift Charts` for local quota history.

## Provider contract

Each provider returns a `ProviderSnapshot` containing connection state, a quota window, source label, update time, and optional local history. The UI does not know how credentials work.

### Codex

Primary: spawn the local `codex app-server`, complete the documented initialization handshake, and read `account/rateLimits/read`. The client extracts only percentage and reset metadata.

Fallback: invoke an installed CodexBar CLI in read-only JSON mode.

### Claude

MVP: invoke an installed CodexBar CLI in read-only JSON mode. It can reuse a Claude session already connected locally. The app does not inspect cookies or tokens.

Before public stable release, replace the compatibility bridge with a documented/maintainable standalone provider or explicitly package the dependency and its attribution.

## Privacy

- Provider outputs are sanitized before messages reach the UI.
- Account identities are discarded.
- Task router is deterministic and local.
- Only daily quota percentages are written to Application Support.
