#!/bin/bash
# Builds, signs, and notarizes a distributable Burrow disk image.
set -euo pipefail

usage() {
    printf 'Usage: %s [developer-id-certificate-hash [notary-profile]]\n' "${0##*/}"
    printf 'Defaults to the only valid Developer ID Application identity and the Burrow Notary profile.\n'
}

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    usage
    exit 0
fi
if [[ $# -gt 2 || ( $# -gt 0 && ! "$1" =~ ^[[:xdigit:]]{40}$ ) ]]; then
    usage >&2
    exit 2
fi

requested_identity="${1:-}"
profile="${2:-Burrow Notary}"
identities="$(security find-identity -v -p codesigning)"
matches="$(awk -v hash="$requested_identity" '
    /"Developer ID Application:/ && (hash == "" || $2 == toupper(hash)) { print $2 }
' <<< "$identities" | sort -u)"
case "$matches" in
    '')
        printf 'No matching Developer ID Application signing identity. See the release setup in README.md.\n' >&2
        exit 1
        ;;
    *$'\n'*)
        printf 'Multiple Developer ID Application identities found. Pass the desired certificate hash:\n' >&2
        awk '/"Developer ID Application:/' <<< "$identities" >&2
        exit 1
        ;;
    *) identity="$matches" ;;
esac

if ! xcrun notarytool history --keychain-profile "$profile" --output-format json >/dev/null; then
    printf 'Could not access the notary service with profile "%s". See the release setup in README.md.\n' "$profile" >&2
    exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
mkdir -p build
work="$(mktemp -d "$root/build/.release-dmg.XXXXXX")"
trap 'rm -rf "$work"' EXIT

staging="$work/staging"
app="$staging/Burrow.app"
scripts/build-app.sh release "$staging"
version="$(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist")"
output="$root/build/Burrow-$version.dmg"
if [[ -e "$output" || -L "$output" ]]; then
    printf 'Release already exists at %s\n' "$output" >&2
    exit 1
fi

codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

ln -s /Applications "$staging/Applications"
dmg="$work/Burrow.dmg"
hdiutil create -srcfolder "$staging" -volname Burrow -format UDZO "$dmg"
codesign --timestamp --sign "$identity" --identifier com.mariusfanu.burrow.dmg "$dmg"

result="$work/notarization.plist"
printf 'Submitting the signed DMG to Apple for notarization.\n'
if ! xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait --output-format plist > "$result"; then
    cat "$result" >&2
    exit 1
fi
status="$(plutil -extract status raw -o - "$result")"
submission_id="$(plutil -extract id raw -o - "$result")"
printf 'Notarization %s (submission %s)\n' "$status" "$submission_id"
if [[ "$status" != Accepted ]]; then
    printf 'View the notarization log with xcrun notarytool log %q --keychain-profile %q\n' "$submission_id" "$profile" >&2
    exit 1
fi

xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
codesign --verify --verbose=2 "$dmg"

# Publish only the verified image. link fails if another release already created this path.
link "$dmg" "$output"
printf 'Release DMG: %s\n' "$output"
