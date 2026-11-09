#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(tr -d '\n' < "$ROOT/VERSION")
REPOSITORY=ensomnia16/WillowFan
FEED_PATH=updates/v2/appcast.xml
TAG="v$VERSION"
cd "$ROOT"
[[ -z $(git status --porcelain) ]] || { echo 'Commit all source changes before publishing.' >&2; exit 1; }
git fetch origin main
COMMIT=$(git rev-parse HEAD)
[[ "$COMMIT" == $(git rev-parse origin/main) ]] || { echo 'Push the release commit to origin/main first.' >&2; exit 1; }
OUT="$ROOT/build.noindex/releases/$VERSION"
if [[ "${1:-}" != --skip-build ]]; then
    bash Scripts/test.sh
    bash Scripts/package.sh
fi
ARCHIVE="WillowFan-$VERSION-arm64.zip"
(cd "$OUT" && shasum -a 256 -c SHA256SUMS)

if ! gh release view "$TAG" --repo "$REPOSITORY" >/dev/null 2>&1; then
    gh release create "$TAG" "$OUT/$ARCHIVE" "$OUT/appcast.xml" "$OUT/SHA256SUMS" \
        --repo "$REPOSITORY" --target "$COMMIT" --latest=false \
        --title "柳风 $VERSION" --notes-file "$ROOT/docs/releases/$VERSION.md"
fi
[[ $(gh api "repos/$REPOSITORY/commits/$TAG" --jq .sha) == "$COMMIT" ]]
VERIFY_DIR=$(mktemp -d "$OUT/verify.XXXXXX")
trap 'rm -rf "$VERIFY_DIR"' EXIT
for asset in "$ARCHIVE" appcast.xml SHA256SUMS; do
    curl --fail --silent --show-error --location --retry 2 \
        "https://github.com/$REPOSITORY/releases/download/$TAG/$asset" -o "$VERIFY_DIR/$asset"
    cmp "$OUT/$asset" "$VERIFY_DIR/$asset"
done

FEED_SHA=$(git rev-parse --verify "origin/main:$FEED_PATH" 2>/dev/null || true)
if [[ "$FEED_SHA" != "$(git hash-object "$OUT/appcast.xml")" ]]; then
    jq -n --arg message "Publish WillowFan $VERSION update feed" \
        --arg content "$(base64 < "$OUT/appcast.xml" | tr -d '\n')" --arg sha "$FEED_SHA" \
        '{message: $message, content: $content, branch: "main"} + (if $sha == "" then {} else {sha: $sha} end)' |
        gh api --method PUT "repos/$REPOSITORY/contents/$FEED_PATH" --input - --jq .commit.sha
fi
