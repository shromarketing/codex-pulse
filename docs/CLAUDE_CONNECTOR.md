# Claude Web Connector

## What it does

Pulse Connector reads the same quota aggregates shown on the signed-in Claude Usage page and sends only percentages, reset timestamps, model-window names, capture time, and a sanitized plan label to Codex Pulse.

It does not send browser cookies, session headers, email, chat titles, messages, prompts, or page content.

## Local install for development

1. Build and open `CodexPulse.app`.
2. In Chrome, open `chrome://extensions`, enable Developer mode, choose **Load unpacked**, and select the folder revealed by **Settings → Services → Show extension folder**. For source builds, that folder is `BrowserExtension/PulseConnector`. Install it in the same Chrome profile where `claude.ai` is signed in.
3. In Codex Pulse, open **Settings → Services**, select **Pulse Connector**, and create a pairing code.
4. Open the extension popup, enter the eight-character code, and press **Pair**.
5. Press **Refresh** once. Later updates run when a Claude tab completes loading and every two minutes while Chrome is running.

## Security model

- The app listens only on `127.0.0.1:37421`.
- Pairing codes expire after ten minutes; repeated invalid attempts are temporarily blocked.
- Pairing returns a random 256-bit token. Chrome stores the raw token for the extension; Pulse stores only its SHA-256 hash.
- Disconnecting in Pulse or the extension revokes the local relationship.
- Payloads are schema-validated, capped by the local HTTP receiver, and contain no Claude credential fields.

## Troubleshooting

- **No Claude tab:** open `https://claude.ai`, sign in, then press Refresh in the extension.
- **Pairing expired:** create a new code in Pulse and pair again.
- **Pulse is not reachable:** launch the latest `CodexPulse.app` before pairing or refreshing.
- **No quota windows:** reload Claude and verify the Usage page shows limits for the current account.

The optional legacy CodexBar source remains available for accounts or environments where the extension cannot run. It has a separate consent step because it may read Chrome cookies and use macOS Keychain.

## Distribution note

Chrome allows unpacked extensions for trusted local development. Direct one-click installation for the general public requires a Chrome Web Store listing; macOS users cannot silently install a self-hosted extension outside managed enterprise policy. The public preview therefore keeps this step visible and user-controlled.
