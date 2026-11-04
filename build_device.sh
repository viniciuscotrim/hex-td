#!/bin/bash
# Build + deploy no iPhone FÍSICO. Descoberta (01/jul/2026): o crash do xcodebuild
# no Xcode 26 só ocorre mirando o device PAREADO; mirando 'generic/platform=iOS'
# ele builda e ASSINA normalmente (usa o profile curinga de 1 ano da conta paga
# U3H5DHZP65). Depois instala via devicectl (que não crasha). Sem swiftc manual.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJ="$ROOT/HexTD.xcodeproj"
DD="${HEXTD_BUILD:-$HOME/Library/Caches/HexTDBuild}/DD"   # LOCAL, fora do iCloud
APP="$DD/Build/Products/Debug-iphoneos/HexTD.app"
DEVICE="${DEVICE:-A495656F-4801-515B-9900-E7989FCB561A}"   # iPhone 17 Pro

echo "▸ build + assinatura (device genérico, provisioning automático)…"
xcodebuild -project "$PROJ" -scheme HexTD \
  -destination 'generic/platform=iOS' -configuration Debug \
  -derivedDataPath "$DD" -allowProvisioningUpdates build \
  | tail -3

echo "▸ instalando no iPhone $DEVICE (desbloqueie o aparelho)…"
xcrun devicectl device install app --device "$DEVICE" "$APP"
echo "✅ instalado: com.hextd.HexTD"
