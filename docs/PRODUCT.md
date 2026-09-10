# Product definition

## Promise

Codex Pulse tells a user what AI quota is left, whether their current pace is safe, and which provider/model/effort is the sensible next choice.

Version 0.5.0 adds explicit Claude Web connection and keeps its session, weekly, and model-specific quota windows visible across the dashboard, menu, and expanded widget. The recommended bundled Pulse Connector keeps cookies inside Chrome and sends only sanitized quotas over localhost. The legacy CodexBar bridge may cache an encrypted session header in macOS Keychain only after separate explicit consent.

## Audiences

- Beginner: wants a plain-language answer and safe defaults.
- Professional: wants exact windows, resets, source confidence, history, and fast access.

## Core surfaces

1. Menu bar: immediate status with a user-selected representation.
2. Floating widget: resizable Mini, Compact, Focus, and Adaptive views.
3. Dashboard: quota details, pace forecast, usage intelligence, daily drill-down, usage history, task router, and settings.

Disconnected providers stay out of the default Simple experience. A user can reveal them in Pro mode, but a public service-health signal never masquerades as an authenticated provider connection.

## Product boundaries

- Read-only by default.
- Never claims it switched a model.
- Never invents a numeric task cost before execution.
- Never reads prompt or chat content automatically.
- Never imports a browser session without an explicit, reversible user confirmation.
- Sends only the task explicitly typed into AI routing, only after the user presses the action; Local mode remains on-device and quota-free.
- Cost and task-size figures are always labeled as estimates.
- Usage history is grouped by project and day unless a provider exposes exact per-task metadata without message content.
- Provider disconnection is a normal state, not a fake zero.
