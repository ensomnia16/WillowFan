#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(tr -d '\n' < "$ROOT/VERSION")
if [[ "${1:-}" != --skip-build ]]; then bash "$ROOT/Scripts/build.sh"; fi
APP="$ROOT/build.noindex/柳风.app"
OUT="$ROOT/build.noindex/releases/$VERSION"
mkdir -p "$OUT"
ARCHIVE="$OUT/WillowFan-$VERSION-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
rm -f "$OUT/appcast.xml"
cp "$ROOT/docs/releases/$VERSION.md" "$OUT/WillowFan-$VERSION-arm64.md"
"$ROOT/.deps.noindex/Sparkle/bin/generate_appcast" \
    --account com.willowfan.app \
    --download-url-prefix "https://github.com/ensomnia16/WillowFan/releases/download/v$VERSION/" \
    --link https://github.com/ensomnia16/WillowFan \
    --embed-release-notes --maximum-deltas 0 -o "$OUT/appcast.xml" "$OUT"
"$ROOT/.deps.noindex/Sparkle/bin/sign_update" --account com.willowfan.app --verify "$OUT/appcast.xml"
(cd "$OUT" && shasum -a 256 "WillowFan-$VERSION-arm64.zip" > SHA256SUMS)
echo "$OUT"
