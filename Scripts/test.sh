#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_root="${script_dir:h}"
developer_dir="$(xcode-select -p)"
test_cache_root="${TMPDIR:-/private/tmp}/codex-pulse-tests"

# macOS beta CLT can briefly ship a default SDK one patch newer than swiftc.
# Pulse targets macOS 13 APIs, so prefer the bundled compatible fallback SDK.
if [[ -z "${SDKROOT:-}" && -d "$developer_dir/SDKs/MacOSX26.5.sdk" ]]; then
    export SDKROOT="$developer_dir/SDKs/MacOSX26.5.sdk"
fi

cd "$project_root"
mkdir -p "$test_cache_root/clang-cache"
export CLANG_MODULE_CACHE_PATH="$test_cache_root/clang-cache"
node "$project_root/Scripts/test-extension.mjs"

if [[ -d "$developer_dir/Platforms/MacOSX.platform" ]]; then
    exec swift test --disable-sandbox --disable-xctest --enable-swift-testing "$@"
fi

framework_path="$developer_dir/Library/Developer/Frameworks"
library_path="$developer_dir/Library/Developer/usr/lib"
testing_macros="$developer_dir/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"

if [[ ! -f "$testing_macros" ]]; then
    print -u2 "Codex Pulse tests: Swift Testing macro plugin was not found."
    print -u2 "Install the matching Apple Command Line Tools or full Xcode and retry."
    exit 1
fi

swift build \
    --disable-sandbox \
    --build-tests \
    --disable-xctest \
    --enable-swift-testing \
    -Xswiftc -load-plugin-library \
    -Xswiftc "$testing_macros" \
    "$@"
bin_path="$(swift build --show-bin-path --disable-sandbox 2>/dev/null | tail -n 1)"
test_binary="$bin_path/CodexPulseTests.xctest/Contents/MacOS/CodexPulseTests"
test_helper="$developer_dir/usr/libexec/swift/pm/swiftpm-testing-helper"

if [[ ! -x "$test_binary" || ! -x "$test_helper" || ! -d "$framework_path/Testing.framework" ]]; then
    print -u2 "Codex Pulse tests: compatible Swift Testing runtime was not found."
    print -u2 "Install the matching Apple Command Line Tools or full Xcode and retry."
    exit 1
fi

DYLD_FRAMEWORK_PATH="$framework_path" \
DYLD_LIBRARY_PATH="$library_path" \
    "$test_helper" \
        --test-bundle-path "$test_binary" \
        --disable-sandbox \
        "$test_binary" \
        --testing-library swift-testing
