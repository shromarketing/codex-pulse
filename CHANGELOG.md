# Changelog

All notable changes to Codex Pulse are documented here.

## [Unreleased]

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
