# Privacy

Codex Pulse is designed to work locally and in read-only mode.

It does not read chat history or store prompt text, chat content, passwords, cookies, access tokens, or account email addresses. It stores app preferences and timestamped quota percentages on the current Mac. Optional usage intelligence consumes only aggregate token, model, project-folder, date, and estimated-cost data returned by local providers. There is no hidden telemetry.

When the user explicitly enables **Claude Web**, the bundled Pulse Connector performs read-only Usage requests inside the already signed-in `claude.ai` tab. Browser cookies, session headers, account email, and chat content never leave Chrome. The extension sends only quota percentages, reset timestamps, and a sanitized plan label to the loopback-only Pulse bridge. Pairing uses a short-lived one-time code and a revocable random token; Pulse persists only the token's SHA-256 hash. The legacy CodexBar fallback can be enabled separately and may use macOS Keychain after explicit consent.

When a user explicitly chooses **AI analysis** and presses **Ask Codex**, Pulse sends only the task text typed into the router to the locally signed-in Codex CLI. The classifier runs as an ephemeral Codex request and Pulse does not persist the task or create a reusable API key. This request uses a small amount of the user's Codex quota. **Local** mode never sends the task and uses no provider quota.

Provider errors are sanitized before display. Historical “receipts” are explicitly grouped by project and day rather than presented as exact chat-level billing. Users may delete local history by removing the CodexPulse Application Support folder.
