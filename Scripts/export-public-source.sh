#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
destination="${1:-}"

if [[ -z "$destination" ]]; then
    print -u2 "Usage: ./Scripts/export-public-source.sh /absolute/path/to/empty-folder"
    exit 1
fi
destination="${destination:A}"
if [[ "$destination" == "$project_root" || "$destination" == "$project_root"/* ]]; then
    print -u2 "Choose a destination outside the working repository."
    exit 1
fi
if [[ -e "$destination" && -n "$(find "$destination" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    print -u2 "Destination must be empty: $destination"
    exit 1
fi

mkdir -p "$destination/Resources" "$destination/docs"

public_files=(
    .gitignore
    CHANGELOG.md
    CONTRIBUTING.md
    INSTALL_WITH_AI.md
    INSTALL_WITH_AI.ru.md
    LICENSE
    Package.swift
    PRIVACY.md
    README.md
    README.ru.md
    SECURITY.md
    SUPPORT.md
)
public_directories=(
    .github
    BrowserExtension/PulseConnector
    Scripts
    Sources/CodexPulse
    Tests/CodexPulseTests
)
public_docs=(
    ARCHITECTURE.md
    CLAUDE_CONNECTOR.md
    ROADMAP.md
    assets/overview-dark.jpg
)
public_resources=(
    AppIcon.icns
    AppIcon.png
    Info.plist
)

for item in "${public_files[@]}"; do
    /usr/bin/ditto "$project_root/$item" "$destination/$item"
done
for item in "${public_directories[@]}"; do
    mkdir -p "$destination/${item:h}"
    /usr/bin/ditto "$project_root/$item" "$destination/$item"
done
for item in "${public_docs[@]}"; do
    mkdir -p "$destination/docs/${item:h}"
    /usr/bin/ditto "$project_root/docs/$item" "$destination/docs/$item"
done
for item in "${public_resources[@]}"; do
    /usr/bin/ditto "$project_root/Resources/$item" "$destination/Resources/$item"
done

find "$destination" -name '.DS_Store' -delete

blocked_references="$(find "$destination" -type f \
    ! -path "$destination/Scripts/export-public-source.sh" \
    -print0 | xargs -0 rg -n \
        -e '/Users/' \
        -e 'sharafutdinov\.roman@gmail\.com' \
        -e 'implementation-screenshot\.png' \
        -e 'design-comparison\.png' || true)"
if [[ -n "$blocked_references" ]]; then
    print -u2 "$blocked_references"
    print -u2 "Public export contains a blocked private reference."
    exit 1
fi

git -C "$destination" init -b main >/dev/null
print "Clean public source prepared at: $destination"
print "Review it, run ./Scripts/test.sh, then create the first commit."
