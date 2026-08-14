# Security policy

Codex Pulse is read-only by design. It must not collect prompt bodies, chat contents, cookies, passwords, API keys, access tokens, account emails or hidden analytics.

## Reporting a vulnerability

Please use GitHub **Security → Report a vulnerability** instead of opening a public issue for:

- credential or cookie exposure;
- unsafe command execution or privilege escalation;
- a localhost bridge accessible outside loopback;
- cross-profile data leakage;
- unexpected network transmission;
- privacy-sensitive data written to logs or history.

Include the affected version, macOS version, reproduction steps and expected impact. Remove all real credentials and account data. Please allow a reasonable private remediation period before public disclosure.

## Supported versions

During the public preview, only the latest GitHub release and current `main` revision receive fixes.

## Unsigned preview

Current binaries are ad-hoc signed but not Developer ID signed or notarized. Verify `SHA256SUMS`, inspect the source, or use the local agent-build route. The project never asks users to disable Gatekeeper, remove quarantine attributes or run an installer with `sudo`.
