#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
install_root="${CODEX_PULSE_INSTALL_DIR:-$HOME/Applications}"
installed_app="$install_root/Codex Pulse.app"
backup_app="$install_root/Codex Pulse.backup.$(date +%Y%m%d-%H%M%S).app"

if [[ "$(uname -s)" != "Darwin" ]]; then
    print -u2 "Codex Pulse supports macOS only."
    exit 1
fi
if ! command -v swift >/dev/null 2>&1 || ! xcode-select -p >/dev/null 2>&1; then
    print -u2 "Apple Command Line Tools are required. Run: xcode-select --install"
    exit 1
fi

cd "$project_root"
"$project_root/Scripts/test.sh"
"$project_root/Scripts/build-app.sh" release native
codesign --verify --deep --strict "$project_root/CodexPulse.app"

mkdir -p "$install_root"
if [[ -d "$installed_app" ]]; then
    mv "$installed_app" "$backup_app"
    print "Previous app preserved at: $backup_app"
fi
/usr/bin/ditto "$project_root/CodexPulse.app" "$installed_app"
codesign --verify --deep --strict "$installed_app"

print "Installed: $installed_app"
print "No sudo was used and macOS security settings were not disabled."
print "Launch it from Finder or run: open '$installed_app'"
