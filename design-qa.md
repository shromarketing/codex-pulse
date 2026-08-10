# Design QA

- source: `Resources/design-reference.png`
- implementation: `implementation-screenshot.png`
- combined comparison: `design-comparison.png`
- viewport: reference normalized to 1080x760; implementation captured at 1080x760
- review rounds: 2

## Visible review

- P0: none.
- P1: none after the second pass.
- P2: the implementation intentionally uses a normal native macOS window instead of the reference's composited desktop scene; live Claude is shown disconnected rather than with mock quota data.
- Preserved: graphite hierarchy, compact sidebar, teal/orange provider coding, quota ring, history surface, task-routing surface, settings density, and native window behavior.
- Verified interactions: task input and recommendation, RU/EN, light/dark, floating-widget toggle, refresh control, and navigation.

## Data-state review

- Codex card was captured from the live read-only `Codex App Server` source.
- Claude is deliberately shown as not connected on this Mac; no fake provider data was introduced for visual parity.

final result: passed
