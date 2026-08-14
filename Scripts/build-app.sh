#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
configuration="${1:-release}"
architecture_mode="${2:-universal}"
output_app="$project_root/CodexPulse.app"
configuration_title="${(C)configuration}"
developer_dir="$(xcode-select -p)"
build_flags=()
if [[ "$configuration" == "release" ]]; then
    build_flags=(-debug-info-format none)
    # This optimization appeared in newer SwiftPM releases. GitHub's stable
    # macOS runner can lag behind beta Command Line Tools, so enable it only
    # when the active toolchain advertises support.
    if swift build -help 2>&1 | grep -q -- '--enable-experimental-strip-products'; then
        build_flags+=(--enable-experimental-strip-products)
    fi
fi

cd "$project_root"

# macOS beta CLT can briefly ship a default SDK one patch newer than swiftc.
# Pulse targets macOS 13 APIs, so prefer the bundled compatible fallback SDK.
if [[ -z "${SDKROOT:-}" && -d "$developer_dir/SDKs/MacOSX26.5.sdk" ]]; then
    export SDKROOT="$developer_dir/SDKs/MacOSX26.5.sdk"
fi

export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$project_root/.build/module-cache}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$project_root/.build/clang-module-cache}"

mkdir -p "$output_app/Contents/MacOS" "$output_app/Contents/Resources"

if [[ "$architecture_mode" == "universal" ]]; then
    arm_scratch="$project_root/.build/codexpulse-arm64"
    intel_scratch="$project_root/.build/codexpulse-x86_64"
    if ! swift build --disable-sandbox -c "$configuration" "${build_flags[@]}" --triple arm64-apple-macosx13.0 --scratch-path "$arm_scratch"; then
        [[ -x "$arm_scratch/out/Products/$configuration_title/CodexPulse" ]] || exit 1
    fi
    if ! swift build --disable-sandbox -c "$configuration" "${build_flags[@]}" --triple x86_64-apple-macosx13.0 --scratch-path "$intel_scratch"; then
        # Some Command Line Tools installations finish the Intel binary but fail
        # only while generating its optional dSYM. Package the verified binary.
        [[ -x "$intel_scratch/out/Products/$configuration_title/CodexPulse" ]] || exit 1
    fi
    lipo -create \
        "$arm_scratch/out/Products/$configuration_title/CodexPulse" \
        "$intel_scratch/out/Products/$configuration_title/CodexPulse" \
        -output "$output_app/Contents/MacOS/CodexPulse"
else
    swift build --disable-sandbox -c "$configuration" "${build_flags[@]}"
    binary_path="$(swift build --disable-sandbox -c "$configuration" "${build_flags[@]}" --show-bin-path)/CodexPulse"
    cp "$binary_path" "$output_app/Contents/MacOS/CodexPulse"
fi

cp "$project_root/Resources/Info.plist" "$output_app/Contents/Info.plist"
/usr/bin/ditto \
    "$project_root/BrowserExtension/PulseConnector" \
    "$output_app/Contents/Resources/PulseConnector"

if [[ -f "$project_root/Resources/AppIcon.icns" ]]; then
    cp "$project_root/Resources/AppIcon.icns" "$output_app/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$output_app/Contents/Info.plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$output_app/Contents/Info.plist"
fi

codesign --force --deep --sign - "$output_app"
file "$output_app/Contents/MacOS/CodexPulse"
echo "$output_app"
