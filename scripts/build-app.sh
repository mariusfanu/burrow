#!/bin/bash
# Builds Burrow.app from the Swift package.
# Usage: scripts/build-app.sh [debug|release] [output-directory]
set -euo pipefail

configuration="${1:-release}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ $# -ge 2 ] && [ -n "$2" ]; then
    case "$2" in
        /*) output_directory="$2" ;;
        *) output_directory="$(pwd)/$2" ;;
    esac
else
    output_directory="$root/build"
fi
cd "$root"

bundle_version="$(awk -F'"' '/^[[:space:]]*MARKETING_VERSION:/ { print $2 }' project.yml)"
bundle_build="$(awk -F'"' '/^[[:space:]]*CURRENT_PROJECT_VERSION:/ { print $2 }' project.yml)"
if [ -z "$bundle_version" ] || [ -z "$bundle_build" ]; then
    echo "Couldn't read the version from project.yml" >&2
    exit 1
fi

swift build -c "$configuration" --product Burrow
binary="$(swift build -c "$configuration" --show-bin-path)/Burrow"

app="$output_directory/Burrow.app"
rm -rf "$app" # SAFE: rebuilds this script's own output directory.
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Burrow"
# GPL-3.0 requires these to travel with the program.
cp LICENSE NOTICE "$app/Contents/Resources/"
if [ -f "Resources/Credits.rtf" ]; then
    cp Resources/Credits.rtf "$app/Contents/Resources/"
fi

temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT # SAFE: mktemp directory created above.
iconset="$temporary_dir/Burrow.iconset"
swift scripts/make-icon.swift "$iconset"
iconutil -c icns "$iconset" -o "$app/Contents/Resources/Burrow.icns"

# Compiles the layered icon, which the system renders as Liquid Glass.
if ! actool_output="$(xcrun actool "$root/Resources/Burrow.icon" \
    --compile "$app/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --app-icon Burrow \
    --include-all-app-icons \
    --output-partial-info-plist "$temporary_dir/icon-info.plist")"; then
    printf '%s\n' "$actool_output" >&2
    exit 1
fi

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>Burrow</string>
    <key>CFBundleIconFile</key><string>Burrow</string>
    <key>CFBundleIconName</key><string>Burrow</string>
    <key>CFBundleIdentifier</key><string>com.mariusfanu.burrow</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Burrow</string>
    <key>CFBundleDisplayName</key><string>Burrow</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$bundle_version</string>
    <key>CFBundleVersion</key><string>$bundle_build</string>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Marius Fanu</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

# The hardened runtime stops a process that can set this app's environment from loading its
# own code into it, which matters because Burrow can hold Full Disk Access.
codesign --force --options runtime --sign - "$app"
echo "Built $app"
