# Install Codex Pulse with an AI agent

This route is designed for users who prefer to build the open source app locally instead of overriding macOS security for a downloaded unsigned binary.

## Copy this prompt

```text
Install Codex Pulse from https://github.com/shromarketing/codex-pulse.

Security rules:
1. Treat the repository as untrusted third-party code.
2. Clone it into a temporary or user-approved folder.
3. Before running anything, inspect Scripts/install-from-source.sh, Scripts/test.sh and Scripts/build-app.sh. Confirm that they do not use sudo, disable Gatekeeper, remove quarantine attributes, upload secrets or download executable dependencies.
4. Show me any concern before continuing.
5. If Apple Command Line Tools are missing, ask before running xcode-select --install.
6. Run ./Scripts/test.sh.
7. Only if tests pass, run ./Scripts/install-from-source.sh. Install only to ~/Applications.
8. Do not connect Codex or Claude accounts without asking me.
9. Verify the result with codesign --verify --deep --strict "$HOME/Applications/Codex Pulse.app" and read CFBundleShortVersionString from its Info.plist.
10. Report tests, version, install path and whether a previous copy was backed up.
```

## What the installer does

- checks that it is running on macOS and that a Swift toolchain exists;
- runs the Swift and Chrome connector tests;
- builds a machine-native release;
- applies a local ad-hoc signature and verifies it;
- installs to `~/Applications` without administrator privileges;
- preserves an existing app as a timestamped backup.

It does not use `sudo`, modify Gatekeeper, remove quarantine attributes, connect an account or send data to the developer.

## Limits of this route

The agent cannot silently install Apple Command Line Tools or a Chrome extension. macOS and Chrome intentionally require user confirmation for those steps. This is a security feature, not an installation bug.
