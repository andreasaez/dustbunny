#!/bin/zsh
# Builds build/Dustbunny.app: release binary, sandbox entitlements, hardened runtime.
# Signs ad-hoc by default; set SIGN_IDENTITY="Developer ID Application: …" to sign for distribution.
# Forks that share their own build should set BUNDLE_ID=com.yourname.Dustbunny.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Dustbunny.app"
IDENTITY="${SIGN_IDENTITY:--}"
BUNDLE_ID="${BUNDLE_ID:-org.dustbunny.Dustbunny}"
[[ "$BUNDLE_ID" =~ '^[A-Za-z0-9.-]+$' ]] || { echo "BUNDLE_ID may only contain letters, digits, '.' and '-'" >&2; exit 1; }

FLAGS=(-c release --product Dustbunny --arch arm64 --arch x86_64)
swift build "${FLAGS[@]}"
BIN="$(swift build "${FLAGS[@]}" --show-bin-path)/Dustbunny"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Dustbunny"
# Privacy: debug symbols record this machine's absolute paths (which contain the user name). Strip them.
strip -S -x "$APP/Contents/MacOS/Dustbunny"
cp Resources/Info.plist "$APP/Contents/Info.plist" # plutil below edits only the bundle copy
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Contents/Info.plist"
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --options runtime --timestamp=none \
  --entitlements Resources/Dustbunny.entitlements \
  --sign "$IDENTITY" "$APP"

codesign --verify --strict --verbose=1 "$APP"
echo "\nEntitlements:"
codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p -
# Refuse to produce an app that contains the build machine's home folder path.
if LC_ALL=C grep -r -q -a -F "$HOME" "$APP"; then
  echo "error: build contains a path from this machine ($HOME); not safe to share" >&2
  exit 1
fi
echo "\nBuilt $APP"
