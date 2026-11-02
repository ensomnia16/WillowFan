#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cargo test --manifest-path "$ROOT/Engine/Cargo.toml"
mkdir -p "$ROOT/build.noindex"
swiftc "$ROOT/App/UnlockGesture.swift" "$ROOT/Tests/main.swift" -o "$ROOT/build.noindex/UnlockGestureTests"
"$ROOT/build.noindex/UnlockGestureTests"
for script in "$ROOT/Scripts/"*.sh; do bash -n "$script"; done
