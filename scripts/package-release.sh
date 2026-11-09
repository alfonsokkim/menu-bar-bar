#!/bin/zsh
set -euo pipefail
root="${0:A:h:h}"
if (( $# > 1 )); then
    print -u2 'Usage: scripts/package-release.sh [path/to/Menu Bar Bar.app]'
    exit 2
fi
: "${MENUBARBAR_SIGN_IDENTITY:?Set MENUBARBAR_SIGN_IDENTITY to a Developer ID Application identity.}"
: "${MENUBARBAR_NOTARY_PROFILE:?Set MENUBARBAR_NOTARY_PROFILE to a notarytool Keychain profile.}"
source_app="${1:-$root/dist/Menu Bar Bar.app}"
source_app="${source_app:A}"
[[ -d "$source_app" ]] || { print -u2 "App not found: $source_app"; exit 1; }
mkdir -p "$root/dist"
rm -f "$root/dist/Menu-Bar-Bar-mac.zip" "$root/dist/SHA256SUMS.txt"
xcrun notarytool history --keychain-profile "$MENUBARBAR_NOTARY_PROFILE" --output-format json >/dev/null
codesign --verify --deep --strict "$source_app"

# Keep a separate signed copy while development continues on the original app.
work=$(mktemp -d "$root/dist/.notarize.XXXXXX")
app="$work/Menu Bar Bar.app"
print -r -- "$app" > "$root/dist/notary-staging-path.txt"
ditto "$source_app" "$app"
codesign --verify --deep --strict "$app"
codesign --force --sign "$MENUBARBAR_SIGN_IDENTITY" --options runtime --timestamp "$app"
signature=$(codesign --display --verbose=4 "$app" 2>&1)
if ! print -r -- "$signature" | grep -q '^Authority=Developer ID Application:'; then
    print -u2 'Distribution requires a Developer ID Application certificate.'
    exit 1
fi
codesign --verify --deep --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$work/Menu-Bar-Bar-submit.zip"
xcrun notarytool submit "$work/Menu-Bar-Bar-submit.zip" \
    --keychain-profile "$MENUBARBAR_NOTARY_PROFILE" --output-format json > "$root/dist/notary-submission.json"
submission=$(plutil -extract id raw -o - "$root/dist/notary-submission.json")
print "Submitted: $submission"
print "Signed staging copy: $app"
xcrun notarytool wait "$submission" --keychain-profile "$MENUBARBAR_NOTARY_PROFILE" \
    --output-format json > "$root/dist/notary-result.json"
xcrun notarytool log "$submission" --keychain-profile "$MENUBARBAR_NOTARY_PROFILE" "$root/dist/notary-log.json"
result=$(plutil -extract status raw -o - "$root/dist/notary-result.json")
[[ "$result" == Accepted ]] || { print -u2 'Notarization was not accepted. See dist/notary-log.json.'; exit 1; }
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict "$app"
spctl --assess --type execute --verbose=2 "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$work/Menu-Bar-Bar-mac.zip"
(cd "$work" && shasum -a 256 Menu-Bar-Bar-mac.zip > SHA256SUMS.txt)
mv "$work/Menu-Bar-Bar-mac.zip" "$work/SHA256SUMS.txt" "$root/dist/"
mkdir -p "$root/dist/notarized"
rm -rf "$root/dist/notarized/Menu Bar Bar.app"
ditto "$app" "$root/dist/notarized/Menu Bar Bar.app"
codesign --verify --deep --strict "$root/dist/notarized/Menu Bar Bar.app"
rm -rf "$work"
print 'Signed, notarized and stapled download: dist/Menu-Bar-Bar-mac.zip'
