#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(tr -d '\n' < "$ROOT/VERSION")
cd "$ROOT"
[[ -z $(git status --porcelain) ]] || { echo 'Commit all source changes before publishing.' >&2; exit 1; }
[[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] || { echo 'Push the release commit to origin/main first.' >&2; exit 1; }
bash Scripts/test.sh
bash Scripts/package.sh
OUT="$ROOT/build.noindex/releases/$VERSION"
gh release create "v$VERSION" "$OUT/WillowFan-$VERSION-arm64.zip" "$OUT/appcast.xml" "$OUT/SHA256SUMS" \
    --repo ensomnia16/WillowFan --target "$(git rev-parse HEAD)" \
    --title "柳风 $VERSION" --notes-file "$ROOT/docs/releases/$VERSION.md"
