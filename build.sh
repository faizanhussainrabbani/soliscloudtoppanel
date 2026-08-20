#!/bin/bash
# Builds SolisSolarMonitor.app without Xcode — Command Line Tools are enough.
#
#   ./build.sh            build into ./dist
#   ./build.sh --install  build, then install to /Applications and launch
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="SolisSolarMonitor"
BUNDLE="dist/${APP_NAME}.app"

echo "==> Compiling (release)"
swift build -c release --product "$APP_NAME"

BIN="$(swift build -c release --product "$APP_NAME" --show-bin-path)/${APP_NAME}"
if [[ ! -x "$BIN" ]]; then
    echo "error: build produced no binary at $BIN" >&2
    exit 1
fi

echo "==> Assembling ${BUNDLE}"
rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
cp "$BIN" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${BUNDLE}/Contents/Info.plist"
cp Resources/AppIcon.icns "${BUNDLE}/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "${BUNDLE}/Contents/PkgInfo"

# Ad-hoc signature. WKWebView and UNUserNotificationCenter both refuse to run
# from an unsigned bundle.
echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - --timestamp=none "$BUNDLE"
codesign --verify --verbose "$BUNDLE" 2>&1 | sed 's/^/    /'

echo "==> Built ${BUNDLE}"

if [[ "${1:-}" == "--install" ]]; then
    echo "==> Installing to /Applications"
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "$BUNDLE" /Applications/
    # Bump mtime so Finder notices the icon changed rather than serving a
    # stale cache entry.
    touch "/Applications/${APP_NAME}.app"
    # Register with LaunchServices so notifications are permitted.
    LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    "$LSREGISTER" -f "/Applications/${APP_NAME}.app"

    # Drop the staging copy. If it survives, LaunchServices keeps it registered
    # alongside the installed one and the app appears twice in Launchpad.
    "$LSREGISTER" -u "$BUNDLE" 2>/dev/null || true
    rm -rf "$BUNDLE"

    open "/Applications/${APP_NAME}.app"
    echo "==> Running. Look for the ☀️ readout in your menu bar."
else
    echo
    echo "Install with:  ./build.sh --install"
    echo "Or run in place:  open ${BUNDLE}"
fi
