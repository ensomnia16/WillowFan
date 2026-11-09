#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP_PATH=${1:-"$ROOT/build.noindex/柳风.app"}
CONTENTS="$APP_PATH/Contents"
VERSION=$(tr -d '\n' < "$ROOT/VERSION")
BUILD_NUMBER=$(tr -d '\n' < "$ROOT/BUILD_NUMBER")
PUBLIC_KEY=$(tr -d '\n' < "$ROOT/UPDATE_PUBLIC_KEY")
bash "$ROOT/Scripts/fetch-sparkle.sh"
SPARKLE="$ROOT/.deps.noindex/Sparkle"
mkdir -p "$ROOT/build.noindex"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cd "$ROOT/Engine"
MACOSX_DEPLOYMENT_TARGET=13.0 cargo build --release --target aarch64-apple-darwin
install -m 755 target/aarch64-apple-darwin/release/macfan "$CONTENTS/Resources/willowfan-engine"
install -m 755 "$ROOT/Scripts/install-service.sh" "$CONTENTS/Resources/install-service.sh"

mkdir -p "$CONTENTS/Frameworks"
ditto "$SPARKLE/Sparkle.framework" "$CONTENTS/Frameworks/Sparkle.framework"
swiftc -O -target arm64-apple-macos13.0 -framework AppKit -framework ApplicationServices -F "$SPARKLE" -framework Sparkle \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks "$ROOT/App/"*.swift "$ROOT/Shared/"*.swift -o "$CONTENTS/MacOS/WillowFan"
swiftc -O -target arm64-apple-macos13.0 -framework AppKit "$ROOT/Shared/WillowMark.swift" "$ROOT/Scripts/make-icon.swift" -o "$ROOT/build.noindex/make-icon"
"$ROOT/build.noindex/make-icon" "$ROOT/build.noindex/icon-1024.png" "$ROOT/build.noindex/WillowMark.svg"
install -m 644 "$ROOT/build.noindex/WillowMark.svg" "$CONTENTS/Resources/WillowMark.svg"
ICONSET="$ROOT/build.noindex/WillowFan.iconset"
mkdir -p "$ICONSET"
for pixel in 16 32 128 256 512; do
    sips -s format png -z "$pixel" "$pixel" "$ROOT/build.noindex/icon-1024.png" --out "$ICONSET/icon_${pixel}x${pixel}.png" >/dev/null
done
for point in 16 32 128 256 512; do
    pixel=$((point * 2))
    sips -s format png -z "$pixel" "$pixel" "$ROOT/build.noindex/icon-1024.png" --out "$ICONSET/icon_${point}x${point}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/WillowFan.icns"
rm -f "$CONTENTS/Resources/WillowFanBright.icns"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>柳风</string>
<key>CFBundleDisplayName</key><string>柳风</string>
<key>CFBundleIdentifier</key><string>com.willowfan.app</string>
<key>CFBundleExecutable</key><string>WillowFan</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>CFBundleIconFile</key><string>WillowFan</string>
<key>LSUIElement</key><false/>
<key>NSHumanReadableCopyright</key><string>© 2026 ensomnia16</string>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>SUFeedURL</key><string>https://github.com/ensomnia16/WillowFan/releases/latest/download/appcast.xml</string>
<key>SUPublicEDKey</key><string>$PUBLIC_KEY</string>
<key>SUEnableAutomaticChecks</key><true/>
<key>SUAutomaticallyUpdate</key><true/>
<key>SUVerifyUpdateBeforeExtraction</key><true/>
<key>SURequireSignedFeed</key><true/>
<key>SUScheduledCheckInterval</key><integer>86400</integer>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Preserve Sparkle's own signed helpers and framework. Sign only our code.
codesign --force --sign - "$CONTENTS/Resources/willowfan-engine" >/dev/null
codesign --force --sign - "$APP_PATH" >/dev/null
codesign --verify --deep --strict "$APP_PATH"
echo "$APP_PATH"
