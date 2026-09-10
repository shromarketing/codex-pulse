# Changelog

All notable changes to Codex Pulse are documented here.

## [Unreleased]

### Added

- Local 30-minute monitor for explicit public Codex reset announcements from Tibo Sottiaux, with a quiet first baseline, deduplication, native notifications, and a link to the original X post.
- A dedicated Signals surface in the menu-bar popover and floating widget, with a manual check that does not refresh quotas or local token analytics.
- Signal cards now use a Russian concise explanation, retain the three newest relevant announcements, and display a defensible estimated moment in Moscow time only when the post supplies enough timing data.
- Signal cards distinguish an early public announcement from the official App Server confirmation for the current account and include an on-demand macOS notification test.

### Changed

- Codex Spark is now hidden from the everyday quota display; Pulse continues to read the main Codex limit from the official App Server.

## [0.5.2] — Single-instance hotfix

### Fixed

- macOS Launch Services now refuses a second Codex Pulse instance, preventing duplicate menu-bar icons and competing local provider bridges.
- The release test script verifies that the single-instance policy remains enabled.

## [0.5.1] — Public preview

### Fixed

- Stable GitHub macOS runners now build release packages without relying on a beta-only SwiftPM optimization flag.
- Notification authorization and delivery compile cleanly under stricter Swift concurrency checking.

### Added

- GitHub public-preview packaging for universal ZIP, DMG, Chrome connector and SHA-256 checksums, with a manually triggered draft-release workflow.
- Safe source installation into `~/Applications` and a copy-ready AI-agent installation workflow.
- Clean public-source export that excludes private screenshots, local paths and internal project files.

### Security

- Claude Pulse Connector bridge is bound explicitly to IPv4 loopback.
- Local HTTP requests have bounded header, body and total sizes.
- Wildcard CORS responses were removed and browser-facing responses add `X-Content-Type-Options: nosniff`.

## [0.5.0] — Public preview candidate

- Unified Codex and Claude quota windows across dashboard, menu bar and desktop widget.
- Separate pace forecasts and local percentage history by provider.
- Claude Web Pulse Connector with opt-in pairing and model-specific weekly windows.
- Local usage, model, project, cost and daily history for providers that expose token aggregates.
- Hybrid local/Codex task routing, Russian/English UI and system/light/dark themes.
