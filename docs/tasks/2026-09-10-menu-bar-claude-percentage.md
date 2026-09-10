# Claude Code percentage in the menu bar

## Result

The `Percent` and `Smart` menu-bar presets show the remaining quotas for both Codex and Claude Code side by side. The status label is one compact native image containing official Codex and Claude icons plus their percentages, so macOS cannot drop a nested icon.

## Context

The account’s Claude browser connection is already configured. The previous Smart preset rendered only the limiting provider; a live review also showed macOS retaining only the first child of the former composite SwiftUI percentage label.

## Scope

- Change only the native SwiftUI menu-bar label.
- Keep the privacy model unchanged: percentages come from the existing local provider snapshots; no cookies, chats, or credentials are read.
- Bundle unchanged official icon files used only for their matching services: Codex from the installed official ChatGPT app and Claude from Anthropic's official press kit.
- Do not change the user’s selected menu-bar preset or publish a release.

## Verification

- Run the project test suite.
- Build the native release application.
- Install locally and relaunch it; verify the app launches and the connected Claude snapshot is available to the menu-bar view.

## Rollback

Restore the Smart branch in `Sources/CodexPulse/Views/MenuBarViews.swift` to the former single limiting-provider layout and rebuild.
