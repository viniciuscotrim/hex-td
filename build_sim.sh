#!/bin/bash
# Build para o SIMULADOR iOS (swiftc + SpriteView, sem xcodebuild). O CÓDIGO mora
# no iCloud (raiz dos apps), mas os ARTEFATOS vão pra pasta LOCAL fora do iCloud
# (senão o iCloud sincroniza/otimiza centenas de MB e quebra o build).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/HexTD"
BUILD="${HEXTD_BUILD:-$HOME/Library/Caches/HexTDBuild}/sim"
APP="$BUILD/HexTD.app"
BUNDLE_ID="com.hextd.HexTD"

SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
TARGET="arm64-apple-ios17.0-simulator"

rm -rf "$BUILD"; mkdir -p "$APP"

echo "▸ compilando swift (sim)…"
xcrun --sdk iphonesimulator swiftc \
  -sdk "$SDK" -target "$TARGET" -swift-version 5 \
  -parse-as-library -Onone -g \
  -o "$APP/HexTD" "$SRC"/*.swift

echo "▸ recursos (áudio + config)…"
cp "$SRC"/Sounds/*.wav "$APP"/ 2>/dev/null || true
cp "$SRC"/progression.json "$APP"/ 2>/dev/null || true

echo "▸ Info.plist…"
PLIST="$APP/Info.plist"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>HexTD</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>HexTD</string>
  <key>CFBundleDisplayName</key><string>Hex TD</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>ITSAppUsesNonExemptEncryption</key><false/>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>MinimumOSVersion</key><string>17.0</string>
  <key>UIDeviceFamily</key><array><integer>1</integer></array>
  <key>UILaunchScreen</key><dict/>
  <key>UISupportedInterfaceOrientations</key>
  <array><string>UIInterfaceOrientationPortrait</string></array>
  <key>UIApplicationSceneManifest</key>
  <dict><key>UIApplicationSupportsMultipleScenes</key><false/></dict>
</dict>
</plist>
EOF
plutil -convert binary1 "$PLIST"

echo "✅ app (sim) montado: $APP"
