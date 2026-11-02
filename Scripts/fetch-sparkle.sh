#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST="$ROOT/.deps.noindex/Sparkle"
VERSION=2.10.1
SHA256=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
if [[ -d "$DEST/Sparkle.framework" && -x "$DEST/bin/generate_appcast" ]]; then exit 0; fi
mkdir -p "$DEST"
ARCHIVE="$ROOT/.deps.noindex/Sparkle-$VERSION.tar.xz"
curl --fail --location --proto '=https' --tlsv1.2 "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz" -o "$ARCHIVE"
printf '%s  %s\n' "$SHA256" "$ARCHIVE" | shasum -a 256 -c -
tar -xf "$ARCHIVE" -C "$DEST"
