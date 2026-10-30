#!/bin/zsh
set -eu
cd "${0:A:h:h}"
configuration="${1:-release}"
if [[ "$configuration" != "release" && "$configuration" != "debug" ]] || (( $# > 2 )); then
    print -u2 "Usage: ./scripts/build-app.sh [release|debug] [output.app]"
    exit 1
fi
signing_mode="${ATLAS_SIGNING_MODE:-development}"
python3 scripts/app-signing.py preflight "$signing_mode"
default_name="Storage Atlas.app"
if [[ "$signing_mode" == "ci" ]]; then default_name="Storage Atlas CI.app"; fi
bundle="${2:-$PWD/dist/$default_name}"
if [[ -f "$bundle/Contents/MacOS/StorageAtlas" ]] && lsof -a -c StorageAtlas -t "$bundle/Contents/MacOS/StorageAtlas" >/dev/null 2>&1; then
    print -u2 "Quit Storage Atlas before packaging. Replacing a running app invalidates its macOS access identity."
    exit 1
fi
swift build --configuration "$configuration"
binary_directory="$(swift build --configuration "$configuration" --show-bin-path)"
swift scripts/generate-app-icon.swift
mkdir -p "${bundle:h}"
staging_directory="$(mktemp -d "${bundle:h}/.atlas-package.XXXXXX")"
staged_bundle="$staging_directory/Storage Atlas.app"
mkdir -p "$staged_bundle/Contents/MacOS" "$staged_bundle/Contents/Resources"
cp "$binary_directory/StorageAtlas" "$staged_bundle/Contents/MacOS/StorageAtlas"
cp Resources/Info.plist "$staged_bundle/Contents/Info.plist"
cp Resources/AppIcon.icns "$staged_bundle/Contents/Resources/AppIcon.icns"
if [[ -f Resources/PrivacyInfo.xcprivacy ]]; then
    cp Resources/PrivacyInfo.xcprivacy "$staged_bundle/Contents/Resources/PrivacyInfo.xcprivacy"
fi
/usr/libexec/PlistBuddy -c "Add :AtlasBuildChannel string $signing_mode" "$staged_bundle/Contents/Info.plist"
framework="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
mkdir -p "$staged_bundle/Contents/Frameworks"
ditto "$framework" "$staged_bundle/Contents/Frameworks/Sparkle.framework"
cp "$PWD/.build/artifacts/sparkle/Sparkle/LICENSE" "$staged_bundle/Contents/Resources/Sparkle-LICENSE"
python3 scripts/app-signing.py sign "$signing_mode" "$staged_bundle"
python3 scripts/app-signing.py compatible "$signing_mode" "$staged_bundle" "$bundle"
# Keep the prior app recoverable and never merge new files into an old signature.
if [[ -e "$bundle" ]]; then mv "$bundle" "$staging_directory/previous.app"; fi
if ! mv "$staged_bundle" "$bundle"; then
    if [[ -e "$staging_directory/previous.app" ]]; then mv "$staging_directory/previous.app" "$bundle"; fi
    exit 1
fi
# Keep rollback data as an archive, not another discoverable app with the same ID.
if [[ -e "$staging_directory/previous.app" ]]; then
    mkdir -p "$PWD/.build/app-backups"
    ditto -c -k --keepParent "$staging_directory/previous.app" "$PWD/.build/app-backups/${staging_directory:t}.zip"
fi
python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1])' "$staging_directory"
# Refresh Finder's bundle metadata when rebuilding an existing app path.
touch "$bundle"
print "Built: $bundle"
