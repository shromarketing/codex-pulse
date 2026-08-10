#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
configuration="${1:-release}"
architecture_mode="${2:-universal}"
output_app="$project_root/CodexPulse.app"
configuration_title="${(C)configuration}"

cd "$project_root"

mkdir -p "$output_app/Contents/MacOS" "$output_app/Contents/Resources"

if [[ "$architecture_mode" == "universal" ]]; then
    arm_scratch="$project_root/.build/codexpulse-arm64"
    intel_scratch="$project_root/.build/codexpulse-x86_64"
    swift build -c "$configuration" --triple arm64-apple-macosx13.0 --scratch-path "$arm_scratch"
    swift build -c "$configuration" --triple x86_64-apple-macosx13.0 --scratch-path "$intel_scratch"
    lipo -create \
        "$arm_scratch/out/Products/$configuration_title/CodexPulse" \
        "$intel_scratch/out/Products/$configuration_title/CodexPulse" \
        -output "$output_app/Contents/MacOS/CodexPulse"
else
    swift build -c "$configuration"
    binary_path="$(swift build -c "$configuration" --show-bin-path)/CodexPulse"
    cp "$binary_path" "$output_app/Contents/MacOS/CodexPulse"
fi

cp "$project_root/Resources/Info.plist" "$output_app/Contents/Info.plist"

if [[ -f "$project_root/Resources/AppIcon.icns" ]]; then
    cp "$project_root/Resources/AppIcon.icns" "$output_app/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$output_app/Contents/Info.plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$output_app/Contents/Info.plist"
fi

codesign --force --deep --sign - "$output_app"
file "$output_app/Contents/MacOS/CodexPulse"
echo "$output_app"
