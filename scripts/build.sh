#!/bin/zsh
# Builds dist/Folga.app (Apple silicon) with Sparkle embedded.
# Signs with the "Folga Local Signing" certificate when it's in the Keychain, ad-hoc otherwise.
set -euo pipefail
cd "${0:A:h}/.."
source ./version.env

SIGN_ID="Folga Local Signing"
FEED_URL="https://raw.githubusercontent.com/guilhermemarketing/folga/main/appcast.xml"
ED_PUBLIC_KEY="94iIAyJFLZIGs98sgDathRSb/q7Q1OGi0tyrW3m8F98="

swift build -c release --arch arm64
BIN=$(swift build -c release --arch arm64 --show-bin-path)
# Assemble and sign outside iCloud Drive: it keeps adding extended attributes that codesign rejects.
STAGE=$(mktemp -d)
APP="$STAGE/Folga.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/Folga" "$APP/Contents/MacOS/Folga"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

ICONSET=$(mktemp -d)/Folga.iconset
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Folga.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Folga</string>
  <key>CFBundleDisplayName</key><string>Folga</string>
  <key>CFBundleIdentifier</key><string>marketing.gui.folga</string>
  <key>CFBundleExecutable</key><string>Folga</string>
  <key>CFBundleIconFile</key><string>Folga</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleDevelopmentRegion</key><string>pt-BR</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Feito para cuidar do disco.</string>
  <key>SUFeedURL</key><string>$FEED_URL</string>
  <key>SUPublicEDKey</key><string>$ED_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict></plist>
PLIST

if security find-certificate -c "$SIGN_ID" >/dev/null 2>&1; then ID="$SIGN_ID"; else ID="-"; echo "Aviso: certificado '$SIGN_ID' não encontrado; assinando ad-hoc."; fi
xattr -cr "$APP"
# Inside out: Sparkle's helpers, the framework, then the app.
FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for item in "$FW"/XPCServices/*.xpc "$FW/Autoupdate" "$FW/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework"; do
  [ -e "$item" ] && codesign --force --sign "$ID" --timestamp=none "$item"
done
codesign --force --sign "$ID" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p dist && rm -rf dist/Folga.app && ditto "$APP" dist/Folga.app && rm -rf "$STAGE"
codesign --verify --deep --strict dist/Folga.app
echo "Pronto: dist/Folga.app ($MARKETING_VERSION, build $BUILD_NUMBER, assinado com: $ID)"
