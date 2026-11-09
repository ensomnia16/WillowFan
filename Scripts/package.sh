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
SPARKLE_BIN="$ROOT/.deps.noindex/Sparkle/bin"
ACCOUNT=com.willowfan.app.v2
[[ $("$SPARKLE_BIN/generate_keys" --account "$ACCOUNT" -p) == "$(tr -d '\n' < "$ROOT/UPDATE_PUBLIC_KEY")" ]] ||
    { echo 'Sparkle signing key does not match UPDATE_PUBLIC_KEY.' >&2; exit 1; }
umask 077
SIGNING_DIR=$(mktemp -d)
trap 'rm -rf "$SIGNING_DIR"' EXIT
"$SPARKLE_BIN/generate_keys" --account "$ACCOUNT" -x "$SIGNING_DIR/key" >/dev/null
"$SPARKLE_BIN/generate_appcast" \
    --ed-key-file "$SIGNING_DIR/key" \
    --download-url-prefix "https://github.com/ensomnia16/WillowFan/releases/download/v$VERSION/" \
    --link https://github.com/ensomnia16/WillowFan \
    --embed-release-notes --maximum-deltas 0 -o "$OUT/appcast.xml" "$OUT"
"$SPARKLE_BIN/sign_update" --ed-key-file "$SIGNING_DIR/key" --verify "$OUT/appcast.xml"
SIGNATURE=$(xmllint --xpath 'string(//*[local-name()="enclosure"]/@*[local-name()="edSignature"])' "$OUT/appcast.xml")
"$SPARKLE_BIN/sign_update" --ed-key-file "$SIGNING_DIR/key" --verify "$ARCHIVE" "$SIGNATURE"
(cd "$OUT" && shasum -a 256 "WillowFan-$VERSION-arm64.zip" > SHA256SUMS)
echo "$OUT"
