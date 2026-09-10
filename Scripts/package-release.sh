#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
architecture_mode="${1:-universal}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_root/Resources/Info.plist")"
dist_dir="$project_root/dist"
app_archive="CodexPulse-${version}-macos-${architecture_mode}.zip"
disk_image="CodexPulse-${version}-macos-${architecture_mode}.dmg"
connector_archive="CodexPulse-Connector-${version}.zip"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-pulse-release.XXXXXX")"

cleanup() {
    rm -rf "$staging_dir"
}
trap cleanup EXIT

cd "$project_root"
"$project_root/Scripts/build-app.sh" release "$architecture_mode"
codesign --verify --deep --strict "$project_root/CodexPulse.app"

mkdir -p "$dist_dir"
find "$dist_dir" -maxdepth 1 -type f \( \
    -name 'CodexPulse-*.zip' -o \
    -name 'CodexPulse-*.dmg' -o \
    -name 'SHA256SUMS' \
\) -delete

/usr/bin/ditto -c -k --sequesterRsrc --keepParent \
    "$project_root/CodexPulse.app" \
    "$dist_dir/$app_archive"
/usr/bin/ditto -c -k --sequesterRsrc \
    "$project_root/BrowserExtension/PulseConnector" \
    "$dist_dir/$connector_archive"

# A DMG provides a familiar drag-to-Applications experience. The app remains
# intentionally ad-hoc signed until the project has a Developer ID certificate.
mkdir -p "$staging_dir/dmg"
/usr/bin/ditto "$project_root/CodexPulse.app" "$staging_dir/dmg/Codex Pulse.app"
ln -s /Applications "$staging_dir/dmg/Applications"
if ! /usr/bin/diskutil image create from \
    --volumeName "Codex Pulse" \
    --format UDZO \
    "$staging_dir/dmg" \
    "$dist_dir/$disk_image" >/dev/null 2>&1; then
    rm -f "$dist_dir/$disk_image"
    /usr/bin/hdiutil create \
        -volname "Codex Pulse" \
        -srcfolder "$staging_dir/dmg" \
        -ov \
        -format UDZO \
        "$dist_dir/$disk_image" >/dev/null
fi

(
    cd "$dist_dir"
    shasum -a 256 "$app_archive" "$disk_image" "$connector_archive" > SHA256SUMS
    shasum -a 256 -c SHA256SUMS
)

print "Release package: $dist_dir/$app_archive"
print "Disk image: $dist_dir/$disk_image"
print "Connector package: $dist_dir/$connector_archive"
print "Checksums: $dist_dir/SHA256SUMS"
