# Contributing to Codex Pulse

Thanks for helping build a calmer way to understand AI usage on macOS.

## Good first contributions

- reproduce and reduce a provider parsing issue using sanitized fixtures;
- improve Russian or English UI copy;
- add VoiceOver labels or keyboard navigation;
- add tests for quota timing, layout boundaries or task-routing guardrails;
- improve setup diagnostics without collecting account data.

## Product invariants

Every change must preserve:

- read-only provider access;
- no chat or prompt collection;
- no hidden telemetry;
- no cookies, credentials, account emails or access tokens stored by Pulse;
- explicit disconnected, stale and estimated states;
- Russian and English copy for every user-facing string;
- macOS 13+ compatibility unless a release decision changes it.

## Local checks

```bash
./Scripts/test.sh
./Scripts/build-app.sh release native
codesign --verify --deep --strict CodexPulse.app
```

For UI changes, verify dashboard, menu popover and all four floating-widget layouts in Russian and English, light and dark appearance. Add a screenshot with sample or anonymized data to the pull request.

## Pull requests

Keep a pull request focused. Explain the user problem, implementation, privacy impact and verification. Never include cookies, raw provider responses, account emails, chat text, client names or absolute user paths in fixtures or screenshots.

By contributing, you agree that your changes are licensed under the project’s MIT license.
